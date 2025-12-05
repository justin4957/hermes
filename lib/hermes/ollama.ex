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
    * `{:error, reason}` - On failure, returns error description

  ## Examples

      iex> Hermes.Ollama.generate("gemma", "Hello")
      {:ok, "Hello! How can I assist you today?"}

      iex> Hermes.Ollama.generate("llama3", "2+2=?", timeout: 10_000)
      {:ok, "2 + 2 = 4"}

      iex> Hermes.Ollama.generate("nonexistent", "test")
      {:error, "HTTP 404: model not found"}
  """
  @spec generate(String.t(), String.t(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
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
      |> handle_response()

    # Calculate duration
    duration = System.monotonic_time() - start_time
    duration_ms = System.convert_time_unit(duration, :native, :millisecond)

    # Emit telemetry stop event and log
    {status, http_status} =
      case result do
        {:ok, _} -> {:ok, 200}
        {:error, msg} when is_binary(msg) -> parse_error_status(msg)
      end

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

  defp parse_error_status(msg) do
    cond do
      String.contains?(msg, "HTTP 4") -> {:error, extract_http_status(msg)}
      String.contains?(msg, "HTTP 5") -> {:error, extract_http_status(msg)}
      String.contains?(msg, "timeout") -> {:timeout, 0}
      String.contains?(msg, "connection") -> {:connection_error, 0}
      true -> {:error, 0}
    end
  end

  defp extract_http_status(msg) do
    case Regex.run(~r/HTTP (\d+)/, msg) do
      [_, status] -> String.to_integer(status)
      _ -> 0
    end
  end

  defp build_url(opts) do
    base_url = Keyword.get(opts, :base_url) || Config.ollama_url()
    "#{base_url}/api/generate"
  end

  defp handle_response({:ok, %{status: 200, body: resp_body}}) do
    case Jason.decode(resp_body) do
      {:ok, %{"response" => response}} ->
        {:ok, response}

      {:ok, parsed} ->
        {:error, "Unexpected response format: #{inspect(parsed)}"}

      {:error, decode_error} ->
        {:error, "JSON decode error: #{inspect(decode_error)}"}
    end
  end

  defp handle_response({:ok, %{status: status, body: body}}) do
    {:error, "HTTP #{status}: #{body}"}
  end

  defp handle_response({:error, reason}) do
    {:error, "Request failed: #{inspect(reason)}"}
  end
end
