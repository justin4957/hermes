defmodule Hermes.Dispatcher do
  @moduledoc """
  Request dispatcher with async task supervision and timeout handling.

  The Dispatcher module acts as a coordination layer between the HTTP router
  and the Ollama client. It manages async task execution using a supervised
  task supervisor, providing fault tolerance and timeout guarantees.

  ## Responsibility

  - Validates that the model is configured before processing
  - Enforces per-model concurrency limits via `Hermes.ModelRegistry`
  - Spawns supervised async tasks for LLM requests
  - Enforces timeout constraints on long-running operations
  - Applies model-specific configuration from `config/config.exs`
  - Handles task failures and exits gracefully
  - Provides consistent error reporting
  - Emits telemetry events for observability

  ## Telemetry Events

  The dispatcher emits the following telemetry events:

  * `[:hermes, :llm, :start]` - Emitted when dispatch starts
  * `[:hermes, :llm, :stop]` - Emitted when dispatch completes
  * `[:hermes, :llm, :exception]` - Emitted on dispatch exception

  ## Model Configuration

  Timeouts are resolved in the following priority:
  1. Explicit `:timeout` option passed to `dispatch/3`
  2. Model-specific timeout from config (e.g., `config :hermes, :models, llama3: %{timeout: 45_000}`)
  3. Default Ollama timeout from config (e.g., `config :hermes, :ollama, timeout: 30_000`)

  ## Design

  Each request is processed in an isolated supervised task, ensuring that:
  1. Failures don't crash the main application
  2. Timeouts are reliably enforced
  3. Resources are properly cleaned up
  4. Multiple concurrent requests can be processed safely

  ## Examples

      # Dispatch with model-specific timeout (from config)
      {:ok, response} = Hermes.Dispatcher.dispatch("gemma", "Hello")

      # Dispatch with explicit timeout (overrides config)
      {:ok, response} = Hermes.Dispatcher.dispatch("llama3", "Long prompt...", timeout: 60_000)

      # Handle timeout
      case Hermes.Dispatcher.dispatch("gemma", "test", timeout: 1) do
        {:ok, _} -> :success
        {:error, "Request timeout after 1ms"} -> :timeout
      end
  """

  require Logger

  alias Hermes.Config
  alias Hermes.Error
  alias Hermes.ModelRegistry
  alias Hermes.Telemetry

  @doc """
  Dispatches an LLM generation request to a supervised async task.

  Creates a supervised task that calls `Hermes.Ollama.generate/3` with the
  provided model and prompt. The task is executed asynchronously with timeout
  protection, ensuring the request completes or times out within the specified
  duration.

  ## Parameters

    * `model` - String name of the Ollama model to use
    * `prompt` - String containing the text prompt
    * `opts` - Keyword list of options:
      * `:timeout` - Maximum execution time in milliseconds (default: 30,000)

  ## Returns

    * `{:ok, response}` - Successfully generated response text
    * `{:error, error}` - Structured error (see `Hermes.Error`)

  ## Error Types

  The function may return the following error types:
  - `Hermes.Error.TimeoutError` - Request exceeded timeout
  - `Hermes.Error.InternalError` - Task execution failures or exits
  - Other errors propagated from `Hermes.Ollama`

  ## Examples

      iex> Hermes.Dispatcher.dispatch("gemma", "What is 2+2?")
      {:ok, "The answer is 4."}

      iex> Hermes.Dispatcher.dispatch("gemma", "test", timeout: 1)
      {:error, %Hermes.Error.TimeoutError{timeout_ms: 1, message: "Request timed out after 1ms"}}
  """
  @spec dispatch(String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, Error.error()}
  def dispatch(model, prompt, opts \\ []) do
    request_id = Keyword.get(opts, :request_id, Telemetry.generate_request_id())
    skip_validation = Keyword.get(opts, :skip_validation, false)

    # Set logger metadata for this dispatch
    Logger.metadata(request_id: request_id, model: model)

    # Validate model is configured (can be skipped for testing)
    case validate_model(model, skip_validation) do
      :ok ->
        dispatch_with_concurrency(model, prompt, request_id, opts)

      {:error, _} = error ->
        Logger.warning("Model validation failed",
          request_id: request_id,
          model: model
        )

        error
    end
  end

  defp validate_model(_model, true), do: :ok
  defp validate_model(model, false), do: Config.validate_model(model)

  defp dispatch_with_concurrency(model, prompt, request_id, opts) do
    registry = Keyword.get(opts, :model_registry, ModelRegistry)
    skip_concurrency = Keyword.get(opts, :skip_concurrency, false)

    if skip_concurrency do
      do_dispatch(model, prompt, request_id, opts)
    else
      case registry.acquire(model, registry: registry) do
        {:ok, slot_ref} ->
          try do
            do_dispatch(model, prompt, request_id, opts)
          after
            registry.release(slot_ref, registry: registry)
          end

        {:error, %Error.ConcurrencyLimitError{}} = error ->
          Logger.warning("Concurrency limit reached",
            request_id: request_id,
            model: model
          )

          error
      end
    end
  end

  defp do_dispatch(model, prompt, request_id, opts) do
    # Use model-specific timeout if not explicitly provided
    timeout = Keyword.get(opts, :timeout) || Config.model_timeout(model)
    task_supervisor = Keyword.get(opts, :task_supervisor, Hermes.TaskSupervisor)
    ollama_module = Keyword.get(opts, :ollama_module, Hermes.Ollama)

    # Build options for Ollama, ensuring timeout and request_id are set
    ollama_opts =
      opts
      |> Keyword.drop([
        :task_supervisor,
        :ollama_module,
        :model_registry,
        :skip_validation,
        :skip_concurrency
      ])
      |> Keyword.put(:timeout, timeout)
      |> Keyword.put(:request_id, request_id)

    prompt_length = String.length(prompt)
    start_time = System.monotonic_time()

    # Emit telemetry start event
    :telemetry.execute(
      [:hermes, :llm, :start],
      %{system_time: System.system_time()},
      %{request_id: request_id, model: model, prompt_length: prompt_length, timeout: timeout}
    )

    result =
      try do
        task =
          Task.Supervisor.async_nolink(task_supervisor, fn ->
            # Propagate logger metadata to the task
            Logger.metadata(request_id: request_id, model: model)
            ollama_module.generate(model, prompt, ollama_opts)
          end)

        case Task.await(task, timeout + 1_000) do
          {:ok, response} -> {:ok, response}
          {:error, error} -> {:error, error}
        end
      rescue
        error ->
          Logger.error("Task execution failed",
            request_id: request_id,
            model: model,
            error: inspect(error)
          )

          {:error, Error.InternalError.new("Task execution failed", error)}
      catch
        :exit, {:timeout, _} ->
          Logger.warning("Request timeout",
            request_id: request_id,
            model: model,
            timeout_ms: timeout
          )

          {:error, Error.TimeoutError.new(timeout)}

        :exit, reason ->
          Logger.error("Task exit",
            request_id: request_id,
            model: model,
            reason: inspect(reason)
          )

          {:error, Error.InternalError.new("Task terminated unexpectedly", reason)}
      end

    # Calculate duration and emit telemetry stop event
    duration = System.monotonic_time() - start_time

    {status, response_length} =
      case result do
        {:ok, response} -> {:ok, String.length(response)}
        {:error, _} -> {:error, 0}
      end

    :telemetry.execute(
      [:hermes, :llm, :stop],
      %{duration: duration},
      %{
        request_id: request_id,
        model: model,
        status: status,
        response_length: response_length,
        result: result
      }
    )

    result
  end

  @doc """
  Dispatches a streaming LLM generation request.

  Similar to `dispatch/3`, but streams the response in real-time through
  a callback function. This is useful for displaying partial responses
  to users as they are generated.

  ## Parameters

    * `model` - String name of the Ollama model to use
    * `prompt` - String containing the text prompt
    * `callback` - Function that receives streaming events:
      * `{:chunk, text}` - A partial response chunk
      * `{:done, nil}` - Streaming completed successfully
      * `{:error, error}` - An error occurred
    * `opts` - Keyword list of options:
      * `:timeout` - Maximum execution time in milliseconds (default: 30,000)

  ## Returns

    * `:ok` - Streaming completed successfully
    * `{:error, error}` - Structured error (see `Hermes.Error`)

  ## Examples

      iex> callback = fn
      ...>   {:chunk, text} -> send(self(), {:chunk, text})
      ...>   {:done, nil} -> send(self(), :done)
      ...>   {:error, error} -> send(self(), {:error, error})
      ...> end
      iex> Hermes.Dispatcher.dispatch_stream("gemma", "Hello", callback)
      :ok
  """
  @spec dispatch_stream(String.t(), String.t(), (term() -> any()), keyword()) ::
          :ok | {:error, Error.error()}
  def dispatch_stream(model, prompt, callback, opts \\ []) do
    request_id = Keyword.get(opts, :request_id, Telemetry.generate_request_id())
    skip_validation = Keyword.get(opts, :skip_validation, false)

    # Set logger metadata for this dispatch
    Logger.metadata(request_id: request_id, model: model)

    # Validate model is configured (can be skipped for testing)
    case validate_model(model, skip_validation) do
      :ok ->
        dispatch_stream_with_concurrency(model, prompt, callback, request_id, opts)

      {:error, _} = error ->
        Logger.warning("Model validation failed for streaming request",
          request_id: request_id,
          model: model
        )

        callback.({:error, error})
        error
    end
  end

  defp dispatch_stream_with_concurrency(model, prompt, callback, request_id, opts) do
    registry = Keyword.get(opts, :model_registry, ModelRegistry)
    skip_concurrency = Keyword.get(opts, :skip_concurrency, false)

    if skip_concurrency do
      do_dispatch_stream(model, prompt, callback, request_id, opts)
    else
      case registry.acquire(model, registry: registry) do
        {:ok, slot_ref} ->
          try do
            do_dispatch_stream(model, prompt, callback, request_id, opts)
          after
            registry.release(slot_ref, registry: registry)
          end

        {:error, %Error.ConcurrencyLimitError{}} = error ->
          Logger.warning("Concurrency limit reached for streaming request",
            request_id: request_id,
            model: model
          )

          callback.({:error, error})
          error
      end
    end
  end

  defp do_dispatch_stream(model, prompt, callback, request_id, opts) do
    # Use model-specific timeout if not explicitly provided
    timeout = Keyword.get(opts, :timeout) || Config.model_timeout(model)
    ollama_module = Keyword.get(opts, :ollama_module, Hermes.Ollama)

    # Build options for Ollama, ensuring timeout and request_id are set
    ollama_opts =
      opts
      |> Keyword.drop([
        :task_supervisor,
        :ollama_module,
        :model_registry,
        :skip_validation,
        :skip_concurrency
      ])
      |> Keyword.put(:timeout, timeout)
      |> Keyword.put(:request_id, request_id)

    prompt_length = String.length(prompt)
    start_time = System.monotonic_time()

    # Emit telemetry start event
    :telemetry.execute(
      [:hermes, :llm, :stream, :start],
      %{system_time: System.system_time()},
      %{request_id: request_id, model: model, prompt_length: prompt_length, timeout: timeout}
    )

    Logger.info("Streaming LLM request started",
      request_id: request_id,
      model: model,
      prompt_length: prompt_length,
      timeout: timeout
    )

    # For streaming, we call directly rather than spawning a task
    # since we need to stream chunks back to the caller synchronously
    result = ollama_module.generate_stream(model, prompt, callback, ollama_opts)

    # Calculate duration and emit telemetry stop event
    duration = System.monotonic_time() - start_time
    duration_ms = System.convert_time_unit(duration, :native, :millisecond)

    status = if result == :ok, do: :ok, else: :error

    :telemetry.execute(
      [:hermes, :llm, :stream, :stop],
      %{duration: duration},
      %{
        request_id: request_id,
        model: model,
        status: status,
        result: result
      }
    )

    log_level = if status == :ok, do: :info, else: :warning

    Logger.log(log_level, "Streaming LLM request completed",
      request_id: request_id,
      model: model,
      status: status,
      duration_ms: duration_ms
    )

    result
  end
end
