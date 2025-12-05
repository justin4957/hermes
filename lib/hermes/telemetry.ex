defmodule Hermes.Telemetry do
  @moduledoc """
  Telemetry events and logging for Hermes application.

  This module provides structured logging and telemetry instrumentation for
  observability and debugging. It emits telemetry events for key operations
  and provides helper functions for structured logging with metadata.

  ## Telemetry Events

  The following telemetry events are emitted:

  ### HTTP Request Events

  * `[:hermes, :request, :start]` - Emitted when a request starts
    - Measurements: `%{system_time: integer}`
    - Metadata: `%{request_id: string, method: string, path: string}`

  * `[:hermes, :request, :stop]` - Emitted when a request completes
    - Measurements: `%{duration: integer}` (native time units)
    - Metadata: `%{request_id: string, method: string, path: string, status: integer}`

  * `[:hermes, :request, :exception]` - Emitted on request exception
    - Measurements: `%{duration: integer}`
    - Metadata: `%{request_id: string, kind: atom, reason: term, stacktrace: list}`

  ### LLM Generation Events

  * `[:hermes, :llm, :start]` - Emitted when LLM generation starts
    - Measurements: `%{system_time: integer}`
    - Metadata: `%{request_id: string, model: string, prompt_length: integer}`

  * `[:hermes, :llm, :stop]` - Emitted when LLM generation completes
    - Measurements: `%{duration: integer}`
    - Metadata: `%{request_id: string, model: string, status: atom, response_length: integer}`

  * `[:hermes, :llm, :exception]` - Emitted on LLM generation exception
    - Measurements: `%{duration: integer}`
    - Metadata: `%{request_id: string, model: string, kind: atom, reason: term}`

  ### Ollama Client Events

  * `[:hermes, :ollama, :request, :start]` - Emitted when Ollama HTTP request starts
  * `[:hermes, :ollama, :request, :stop]` - Emitted when Ollama HTTP request completes
  * `[:hermes, :ollama, :request, :exception]` - Emitted on Ollama HTTP exception

  ## Usage

  Attach handlers to these events in your application startup:

      :telemetry.attach_many(
        "hermes-logger",
        [
          [:hermes, :request, :stop],
          [:hermes, :llm, :stop],
          [:hermes, :llm, :exception]
        ],
        &Hermes.Telemetry.handle_event/4,
        nil
      )
  """

  require Logger

  @doc """
  Generates a unique request ID.

  Returns a URL-safe base64-encoded random string suitable for request tracking.

  ## Examples

      iex> request_id = Hermes.Telemetry.generate_request_id()
      iex> is_binary(request_id)
      true
  """
  @spec generate_request_id() :: String.t()
  def generate_request_id do
    :crypto.strong_rand_bytes(16)
    |> Base.url_encode64(padding: false)
  end

  @doc """
  Executes a function with telemetry instrumentation.

  Emits start, stop, and exception events for the given event prefix.

  ## Parameters

    * `event_prefix` - List of atoms for the event name prefix
    * `metadata` - Map of metadata to include with events
    * `fun` - Zero-arity function to execute

  ## Examples

      Hermes.Telemetry.span([:hermes, :llm], %{model: "gemma"}, fn ->
        # Do work
        {:ok, result}
      end)
  """
  @spec span(list(atom()), map(), (-> result)) :: result when result: term()
  def span(event_prefix, metadata, fun) when is_list(event_prefix) and is_function(fun, 0) do
    start_time = System.monotonic_time()

    :telemetry.execute(
      event_prefix ++ [:start],
      %{system_time: System.system_time()},
      metadata
    )

    try do
      result = fun.()

      :telemetry.execute(
        event_prefix ++ [:stop],
        %{duration: System.monotonic_time() - start_time},
        Map.put(metadata, :result, result)
      )

      result
    rescue
      exception ->
        :telemetry.execute(
          event_prefix ++ [:exception],
          %{duration: System.monotonic_time() - start_time},
          Map.merge(metadata, %{
            kind: :error,
            reason: exception,
            stacktrace: __STACKTRACE__
          })
        )

        reraise exception, __STACKTRACE__
    catch
      kind, reason ->
        :telemetry.execute(
          event_prefix ++ [:exception],
          %{duration: System.monotonic_time() - start_time},
          Map.merge(metadata, %{
            kind: kind,
            reason: reason,
            stacktrace: __STACKTRACE__
          })
        )

        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  @doc """
  Default telemetry event handler that logs events.

  Attach this handler to receive structured log output for telemetry events.

  ## Examples

      :telemetry.attach(
        "hermes-logger",
        [:hermes, :request, :stop],
        &Hermes.Telemetry.handle_event/4,
        nil
      )
  """
  @spec handle_event(list(atom()), map(), map(), term()) :: :ok
  def handle_event(event, measurements, metadata, _config) do
    case event do
      [:hermes, :request, :stop] ->
        log_request_complete(measurements, metadata)

      [:hermes, :request, :exception] ->
        log_request_exception(measurements, metadata)

      [:hermes, :llm, :stop] ->
        log_llm_complete(measurements, metadata)

      [:hermes, :llm, :exception] ->
        log_llm_exception(measurements, metadata)

      [:hermes, :ollama, :request, :stop] ->
        log_ollama_complete(measurements, metadata)

      [:hermes, :ollama, :request, :exception] ->
        log_ollama_exception(measurements, metadata)

      _ ->
        :ok
    end
  end

  @doc """
  Logs an HTTP request with structured metadata.

  ## Parameters

    * `conn` - The Plug connection
    * `duration_ms` - Request duration in milliseconds
    * `opts` - Additional options to include in metadata

  ## Examples

      Hermes.Telemetry.log_request(conn, 150, status: 200)
  """
  @spec log_request(Plug.Conn.t(), number(), keyword()) :: :ok
  def log_request(conn, duration_ms, opts \\ []) do
    request_id = get_request_id(conn)
    status = Keyword.get(opts, :status, conn.status)

    metadata = [
      request_id: request_id,
      method: conn.method,
      path: conn.request_path,
      status: status,
      duration_ms: duration_ms
    ]

    level = if status >= 500, do: :error, else: :info

    Logger.log(
      level,
      fn ->
        "#{conn.method} #{conn.request_path} - #{status} (#{format_duration(duration_ms)})"
      end,
      metadata
    )
  end

  @doc """
  Logs an LLM generation request with structured metadata.

  ## Parameters

    * `model` - The model name
    * `prompt_length` - Length of the prompt in characters
    * `duration_ms` - Request duration in milliseconds
    * `opts` - Additional options (`:status`, `:response_length`, `:request_id`, `:error`)
  """
  @spec log_llm_request(String.t(), non_neg_integer(), number(), keyword()) :: :ok
  def log_llm_request(model, prompt_length, duration_ms, opts \\ []) do
    request_id = Keyword.get(opts, :request_id, "unknown")
    status = Keyword.get(opts, :status, :ok)
    response_length = Keyword.get(opts, :response_length, 0)
    error = Keyword.get(opts, :error)

    metadata = [
      request_id: request_id,
      model: model,
      prompt_length: prompt_length,
      response_length: response_length,
      duration_ms: duration_ms,
      status: status
    ]

    metadata = if error, do: Keyword.put(metadata, :error, error), else: metadata

    level = if status == :error, do: :error, else: :info

    Logger.log(
      level,
      fn ->
        case status do
          :ok ->
            "LLM generation complete: model=#{model} prompt_len=#{prompt_length} response_len=#{response_length} (#{format_duration(duration_ms)})"

          :error ->
            "LLM generation failed: model=#{model} prompt_len=#{prompt_length} error=#{inspect(error)} (#{format_duration(duration_ms)})"

          _ ->
            "LLM generation: model=#{model} status=#{status} (#{format_duration(duration_ms)})"
        end
      end,
      metadata
    )
  end

  @doc """
  Gets the request ID from a Plug connection.

  Falls back to generating a new request ID if none is set.
  """
  @spec get_request_id(Plug.Conn.t()) :: String.t()
  def get_request_id(conn) do
    case Plug.Conn.get_resp_header(conn, "x-request-id") do
      [request_id | _] -> request_id
      [] -> generate_request_id()
    end
  end

  @doc """
  Sets the Logger metadata for the current process.

  Useful for propagating request context through async operations.

  ## Parameters

    * `metadata` - Keyword list of metadata to set

  ## Examples

      Hermes.Telemetry.set_logger_metadata(request_id: "abc123", model: "gemma")
  """
  @spec set_logger_metadata(keyword()) :: :ok
  def set_logger_metadata(metadata) do
    Logger.metadata(metadata)
  end

  # Private functions

  defp log_request_complete(measurements, metadata) do
    duration_ms = native_to_ms(measurements.duration)
    status = Map.get(metadata, :status, 200)
    method = Map.get(metadata, :method, "UNKNOWN")
    path = Map.get(metadata, :path, "/")
    request_id = Map.get(metadata, :request_id, "unknown")

    log_metadata = [
      request_id: request_id,
      method: method,
      path: path,
      status: status,
      duration_ms: duration_ms
    ]

    level = if status >= 500, do: :error, else: :info

    Logger.log(
      level,
      fn ->
        "#{method} #{path} - #{status} (#{format_duration(duration_ms)})"
      end,
      log_metadata
    )
  end

  defp log_request_exception(measurements, metadata) do
    duration_ms = native_to_ms(measurements.duration)
    request_id = Map.get(metadata, :request_id, "unknown")
    kind = Map.get(metadata, :kind, :error)
    reason = Map.get(metadata, :reason, "unknown")

    log_metadata = [
      request_id: request_id,
      kind: kind,
      duration_ms: duration_ms
    ]

    Logger.error(
      fn ->
        "Request exception: #{kind} - #{inspect(reason)} (#{format_duration(duration_ms)})"
      end,
      log_metadata
    )
  end

  defp log_llm_complete(measurements, metadata) do
    duration_ms = native_to_ms(measurements.duration)
    model = Map.get(metadata, :model, "unknown")
    request_id = Map.get(metadata, :request_id, "unknown")
    result = Map.get(metadata, :result, nil)

    {status, response_length} =
      case result do
        {:ok, response} when is_binary(response) -> {:ok, String.length(response)}
        {:error, _} -> {:error, 0}
        _ -> {:unknown, 0}
      end

    log_metadata = [
      request_id: request_id,
      model: model,
      status: status,
      response_length: response_length,
      duration_ms: duration_ms
    ]

    level = if status == :error, do: :warning, else: :info

    Logger.log(
      level,
      fn ->
        "LLM #{model}: #{status} response_len=#{response_length} (#{format_duration(duration_ms)})"
      end,
      log_metadata
    )
  end

  defp log_llm_exception(measurements, metadata) do
    duration_ms = native_to_ms(measurements.duration)
    model = Map.get(metadata, :model, "unknown")
    request_id = Map.get(metadata, :request_id, "unknown")
    kind = Map.get(metadata, :kind, :error)
    reason = Map.get(metadata, :reason, "unknown")

    log_metadata = [
      request_id: request_id,
      model: model,
      kind: kind,
      duration_ms: duration_ms
    ]

    Logger.error(
      fn ->
        "LLM #{model} exception: #{kind} - #{inspect(reason)} (#{format_duration(duration_ms)})"
      end,
      log_metadata
    )
  end

  defp log_ollama_complete(measurements, metadata) do
    duration_ms = native_to_ms(measurements.duration)
    status = Map.get(metadata, :status, 200)
    model = Map.get(metadata, :model, "unknown")

    log_metadata = [
      model: model,
      http_status: status,
      duration_ms: duration_ms
    ]

    Logger.debug(
      fn ->
        "Ollama HTTP: #{status} model=#{model} (#{format_duration(duration_ms)})"
      end,
      log_metadata
    )
  end

  defp log_ollama_exception(measurements, metadata) do
    duration_ms = native_to_ms(measurements.duration)
    model = Map.get(metadata, :model, "unknown")
    reason = Map.get(metadata, :reason, "unknown")

    log_metadata = [
      model: model,
      duration_ms: duration_ms
    ]

    Logger.error(
      fn ->
        "Ollama HTTP exception: model=#{model} error=#{inspect(reason)} (#{format_duration(duration_ms)})"
      end,
      log_metadata
    )
  end

  defp native_to_ms(native_time) do
    System.convert_time_unit(native_time, :native, :millisecond)
  end

  defp format_duration(ms) when ms < 1000, do: "#{round(ms)}ms"
  defp format_duration(ms), do: "#{Float.round(ms / 1000, 2)}s"
end
