defmodule Hermes.Ollama do
  @moduledoc """
  HTTP client for interacting with the Ollama REST API.

  This module provides functions for sending generation requests to a locally
  running Ollama instance. It handles request formatting, response parsing,
  and error cases.

  ## Configuration

  The Ollama base URL and timeout can be configured in `config/config.exs`:

      config :hermes, :ollama,
        base_url: "http://localhost:11434",
        timeout: 30_000

  ## Examples

      # Generate text with default timeout
      {:ok, response} = Hermes.Ollama.generate("gemma", "What is Elixir?")

      # Generate with custom timeout
      {:ok, response} = Hermes.Ollama.generate("llama3", "Explain AI", timeout: 60_000)

      # Handle errors
      case Hermes.Ollama.generate("invalid-model", "test") do
        {:ok, response} -> IO.puts(response)
        {:error, reason} -> IO.puts("Error: \#{reason}")
      end
  """

  @behaviour Hermes.OllamaBehaviour

  require Logger

  alias Hermes.Config
  alias Hermes.Error
  alias Hermes.Telemetry

  @doc """
  Generates text completion from an Ollama model.

  Sends a prompt to the specified Ollama model and returns the generated response.
  The request is made in non-streaming mode, returning the complete response once
  generation is finished.

  ## Parameters

    * `model` - String name of the Ollama model to use (e.g., "gemma", "llama3")
    * `prompt` - String containing the text prompt to send to the model
    * `opts` - Keyword list of options:
      * `:timeout` - Request timeout in milliseconds (default: 30,000)

  ## Returns

    * `{:ok, response}` - On success, returns the generated text response
    * `{:error, error}` - On failure, returns a structured error

  ## Error Types

    * `Hermes.Error.ModelNotFoundError` - Model not available in Ollama
    * `Hermes.Error.TimeoutError` - Request exceeded timeout
    * `Hermes.Error.ConnectionError` - Cannot connect to Ollama
    * `Hermes.Error.OllamaError` - Upstream Ollama service error
    * `Hermes.Error.InternalError` - Unexpected internal error

  ## Examples

      iex> Hermes.Ollama.generate("gemma", "Hello")
      {:ok, "Hello! How can I assist you today?"}

      iex> Hermes.Ollama.generate("llama3", "2+2=?", timeout: 10_000)
      {:ok, "2 + 2 = 4"}

      iex> Hermes.Ollama.generate("nonexistent", "test")
      {:error, %Hermes.Error.ModelNotFoundError{model: "nonexistent", message: "..."}}
  """
  @spec generate(String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, Error.error()}
  def generate(model, prompt, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, Config.ollama_timeout())
    request_id = Keyword.get(opts, :request_id, Telemetry.generate_request_id())
    url = build_url(opts)
    finch_name = Keyword.get(opts, :finch_name, Hermes.Finch)

    body =
      Jason.encode!(%{
        model: model,
        prompt: prompt,
        stream: false
      })

    start_time = System.monotonic_time()

    # Emit telemetry start event
    :telemetry.execute(
      [:hermes, :ollama, :request, :start],
      %{system_time: System.system_time()},
      %{request_id: request_id, model: model, url: url, timeout: timeout}
    )

    Logger.debug("Ollama HTTP request starting",
      request_id: request_id,
      model: model,
      url: url,
      timeout: timeout
    )

    result =
      Finch.build(:post, url, [{"content-type", "application/json"}], body)
      |> Finch.request(finch_name, receive_timeout: timeout)
      |> handle_response(model, url, timeout)

    # Calculate duration
    duration = System.monotonic_time() - start_time
    duration_ms = System.convert_time_unit(duration, :native, :millisecond)

    # Emit telemetry stop event and log
    {status, http_status} = error_to_telemetry_status(result)

    :telemetry.execute(
      [:hermes, :ollama, :request, :stop],
      %{duration: duration},
      %{request_id: request_id, model: model, status: status, http_status: http_status}
    )

    log_level = if status == :ok, do: :debug, else: :warning

    Logger.log(log_level, "Ollama HTTP request completed",
      request_id: request_id,
      model: model,
      status: status,
      http_status: http_status,
      duration_ms: duration_ms
    )

    result
  end

  defp error_to_telemetry_status({:ok, _}), do: {:ok, 200}
  defp error_to_telemetry_status({:error, %Error.ModelNotFoundError{}}), do: {:error, 404}
  defp error_to_telemetry_status({:error, %Error.TimeoutError{}}), do: {:timeout, 0}
  defp error_to_telemetry_status({:error, %Error.ConnectionError{}}), do: {:connection_error, 0}

  defp error_to_telemetry_status({:error, %Error.OllamaError{status_code: status}})
       when is_integer(status),
       do: {:error, status}

  defp error_to_telemetry_status({:error, _}), do: {:error, 0}

  defp build_url(opts) do
    base_url = Keyword.get(opts, :base_url) || Config.ollama_url()
    "#{base_url}/api/generate"
  end

  defp handle_response({:ok, %{status: 200, body: resp_body}}, _model, _url, _timeout) do
    case Jason.decode(resp_body) do
      {:ok, %{"response" => response}} ->
        {:ok, response}

      {:ok, parsed} ->
        {:error,
         Error.InternalError.new(
           "Unexpected response format from Ollama",
           inspect(parsed)
         )}

      {:error, decode_error} ->
        {:error,
         Error.InternalError.new(
           "Failed to decode Ollama response",
           inspect(decode_error)
         )}
    end
  end

  defp handle_response({:ok, %{status: 404, body: body}}, model, _url, _timeout) do
    # Model not found
    Logger.debug("Model not found in Ollama", model: model, ollama_response: body)
    {:error, Error.ModelNotFoundError.new(model)}
  end

  defp handle_response({:ok, %{status: status, body: body}}, _model, _url, _timeout)
       when status >= 500 do
    # Ollama server error
    {:error,
     Error.OllamaError.new(
       "Ollama service returned an error",
       status_code: status,
       upstream_error: body
     )}
  end

  defp handle_response({:ok, %{status: status, body: body}}, _model, _url, _timeout) do
    # Other HTTP errors (4xx)
    {:error,
     Error.OllamaError.new(
       "Ollama request failed with status #{status}",
       status_code: status,
       upstream_error: body
     )}
  end

  defp handle_response({:error, %Mint.TransportError{reason: :timeout}}, _model, _url, timeout) do
    {:error, Error.TimeoutError.new(timeout)}
  end

  defp handle_response({:error, %Mint.TransportError{reason: reason}}, _model, url, _timeout) do
    {:error,
     Error.ConnectionError.new(
       "Cannot connect to Ollama service",
       url: url,
       reason: reason
     )}
  end

  defp handle_response({:error, reason}, _model, url, _timeout) do
    {:error,
     Error.ConnectionError.new(
       "Request to Ollama failed",
       url: url,
       reason: reason
     )}
  end

  @doc """
  Generates text completion from an Ollama model with streaming.

  Sends a prompt to the specified Ollama model and streams the generated response
  in real-time. Each chunk is passed to the provided callback function as it arrives.

  The streaming response sends newline-delimited JSON chunks from Ollama, where each
  chunk contains a partial response. This function parses each chunk and invokes the
  callback with the extracted text.

  ## Parameters

    * `model` - String name of the Ollama model to use (e.g., "gemma", "llama3")
    * `prompt` - String containing the text prompt to send to the model
    * `callback` - Function that receives `{:chunk, text}` for each streamed chunk,
      `{:done, nil}` when streaming completes, or `{:error, error}` on failure
    * `opts` - Keyword list of options:
      * `:timeout` - Request timeout in milliseconds (default: 30,000)

  ## Returns

    * `:ok` - Streaming completed successfully
    * `{:error, error}` - On failure, returns a structured error

  ## Callback Events

    * `{:chunk, text}` - A partial response chunk from the model
    * `{:done, nil}` - Streaming has completed successfully
    * `{:error, error}` - An error occurred during streaming

  ## Examples

      iex> callback = fn
      ...>   {:chunk, text} -> IO.write(text)
      ...>   {:done, nil} -> IO.puts("\\n[Done]")
      ...>   {:error, error} -> IO.puts("Error: \#{inspect(error)}")
      ...> end
      iex> Hermes.Ollama.generate_stream("gemma", "Hello", callback)
      :ok

  """
  @spec generate_stream(String.t(), String.t(), (term() -> any()), keyword()) ::
          :ok | {:error, Error.error()}
  def generate_stream(model, prompt, callback, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, Config.ollama_timeout())
    request_id = Keyword.get(opts, :request_id, Telemetry.generate_request_id())
    url = build_url(opts)
    finch_name = Keyword.get(opts, :finch_name, Hermes.Finch)

    body =
      Jason.encode!(%{
        model: model,
        prompt: prompt,
        stream: true
      })

    start_time = System.monotonic_time()

    # Emit telemetry start event
    :telemetry.execute(
      [:hermes, :ollama, :stream, :start],
      %{system_time: System.system_time()},
      %{request_id: request_id, model: model, url: url, timeout: timeout}
    )

    Logger.debug("Ollama streaming request starting",
      request_id: request_id,
      model: model,
      url: url,
      timeout: timeout
    )

    # Create a streaming request handler
    stream_handler = build_stream_handler(callback, request_id)

    result =
      Finch.build(:post, url, [{"content-type", "application/json"}], body)
      |> Finch.stream(finch_name, nil, stream_handler, receive_timeout: timeout)
      |> handle_stream_result(model, url, timeout, callback)

    # Calculate duration
    duration = System.monotonic_time() - start_time
    duration_ms = System.convert_time_unit(duration, :native, :millisecond)

    # Emit telemetry stop event
    {status, http_status} = stream_result_to_telemetry_status(result)

    :telemetry.execute(
      [:hermes, :ollama, :stream, :stop],
      %{duration: duration},
      %{request_id: request_id, model: model, status: status, http_status: http_status}
    )

    log_level = if status == :ok, do: :debug, else: :warning

    Logger.log(log_level, "Ollama streaming request completed",
      request_id: request_id,
      model: model,
      status: status,
      http_status: http_status,
      duration_ms: duration_ms
    )

    result
  end

  defp build_stream_handler(callback, request_id) do
    fn
      {:status, status}, _acc ->
        Logger.debug("Stream status received",
          request_id: request_id,
          status: status
        )

        %{status: status, buffer: ""}

      {:headers, _headers}, acc ->
        Logger.debug("Stream headers received", request_id: request_id)

        acc

      {:data, data}, %{status: status, buffer: buffer} = acc when status == 200 ->
        # Append new data to the buffer and process complete lines
        new_buffer = buffer <> data
        {lines, remaining} = split_into_lines(new_buffer)

        # Process each complete line
        process_stream_lines(lines, callback)

        %{acc | buffer: remaining}

      {:data, _data}, acc ->
        # Non-200 status, just accumulate
        acc

      {:trailers, _trailers}, acc ->
        acc
    end
  end

  defp process_stream_lines(lines, callback) do
    Enum.each(lines, fn line ->
      case parse_stream_chunk(line) do
        {:ok, %{"response" => text, "done" => false}} ->
          callback.({:chunk, text})

        {:ok, %{"done" => true}} ->
          callback.({:done, nil})

        {:ok, _} ->
          # Ignore other fields
          :ok

        {:error, _} ->
          # Skip malformed JSON lines (could be empty lines)
          :ok
      end
    end)
  end

  defp split_into_lines(data) do
    # Split on newlines, keeping the last incomplete line in the buffer
    lines = String.split(data, "\n")

    case lines do
      [] ->
        {[], ""}

      [single] ->
        {[], single}

      multiple ->
        {complete, [remaining]} = Enum.split(multiple, -1)
        {Enum.reject(complete, &(&1 == "")), remaining}
    end
  end

  defp parse_stream_chunk(""), do: {:error, :empty}

  defp parse_stream_chunk(line) do
    Jason.decode(line)
  end

  # Finch.stream returns {:ok, acc} where acc is the final accumulated state
  # Extract the status from the accumulated state
  defp handle_stream_result({:ok, acc}, model, url, timeout, callback) do
    status = extract_status_from_acc(acc)
    handle_stream_status(status, model, url, timeout, callback)
  end

  defp handle_stream_result(
         {:error, %Mint.TransportError{reason: :timeout}, _acc},
         _model,
         _url,
         timeout,
         callback
       ) do
    error = Error.TimeoutError.new(timeout)
    callback.({:error, error})
    {:error, error}
  end

  defp handle_stream_result(
         {:error, %Mint.TransportError{reason: reason}, _acc},
         _model,
         url,
         _timeout,
         callback
       ) do
    error =
      Error.ConnectionError.new(
        "Cannot connect to Ollama service for streaming",
        url: url,
        reason: reason
      )

    callback.({:error, error})
    {:error, error}
  end

  defp handle_stream_result({:error, reason, _acc}, _model, url, _timeout, callback) do
    error =
      Error.ConnectionError.new(
        "Streaming request to Ollama failed",
        url: url,
        reason: reason
      )

    callback.({:error, error})
    {:error, error}
  end

  # Extract status from accumulator structure
  defp extract_status_from_acc(%{status: status}), do: status
  defp extract_status_from_acc(_), do: nil

  defp handle_stream_status(200, _model, _url, _timeout, _callback), do: :ok

  defp handle_stream_status(404, model, _url, _timeout, callback) do
    error = Error.ModelNotFoundError.new(model)
    callback.({:error, error})
    {:error, error}
  end

  defp handle_stream_status(status, _model, _url, _timeout, callback) when status >= 500 do
    error =
      Error.OllamaError.new(
        "Ollama service returned an error during streaming",
        status_code: status
      )

    callback.({:error, error})
    {:error, error}
  end

  defp handle_stream_status(status, _model, _url, _timeout, callback)
       when is_integer(status) do
    error =
      Error.OllamaError.new(
        "Ollama streaming request failed with status #{status}",
        status_code: status
      )

    callback.({:error, error})
    {:error, error}
  end

  defp handle_stream_status(nil, _model, url, _timeout, callback) do
    error =
      Error.ConnectionError.new(
        "Streaming request to Ollama failed - no status received",
        url: url
      )

    callback.({:error, error})
    {:error, error}
  end

  defp stream_result_to_telemetry_status(:ok), do: {:ok, 200}
  defp stream_result_to_telemetry_status({:error, %Error.ModelNotFoundError{}}), do: {:error, 404}
  defp stream_result_to_telemetry_status({:error, %Error.TimeoutError{}}), do: {:timeout, 0}

  defp stream_result_to_telemetry_status({:error, %Error.ConnectionError{}}),
    do: {:connection_error, 0}

  defp stream_result_to_telemetry_status({:error, %Error.OllamaError{status_code: status}})
       when is_integer(status),
       do: {:error, status}

  defp stream_result_to_telemetry_status({:error, _}), do: {:error, 0}
end
