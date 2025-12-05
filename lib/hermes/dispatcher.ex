defmodule Hermes.Dispatcher do
  @moduledoc """
  Request dispatcher with async task supervision and timeout handling.

  The Dispatcher module acts as a coordination layer between the HTTP router
  and the Ollama client. It manages async task execution using a supervised
  task supervisor, providing fault tolerance and timeout guarantees.

  ## Responsibility

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
    * `{:error, reason}` - Error description (timeout, task failure, etc.)

  ## Error Handling

  The function handles several error cases:
  - Task execution failures (exceptions in the worker)
  - Task timeouts (exceeds specified duration)
  - Task exits (abnormal termination)
  - Ollama API errors (propagated from client)

  ## Examples

      iex> Hermes.Dispatcher.dispatch("gemma", "What is 2+2?")
      {:ok, "The answer is 4."}

      iex> Hermes.Dispatcher.dispatch("gemma", "test", timeout: 1)
      {:error, "Request timeout after 1ms"}
  """
  @spec dispatch(String.t(), String.t(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def dispatch(model, prompt, opts \\ []) do
    # Use model-specific timeout if not explicitly provided
    timeout = Keyword.get(opts, :timeout) || Config.model_timeout(model)
    request_id = Keyword.get(opts, :request_id, Telemetry.generate_request_id())
    task_supervisor = Keyword.get(opts, :task_supervisor, Hermes.TaskSupervisor)
    ollama_module = Keyword.get(opts, :ollama_module, Hermes.Ollama)

    # Build options for Ollama, ensuring timeout and request_id are set
    ollama_opts =
      opts
      |> Keyword.drop([:task_supervisor, :ollama_module])
      |> Keyword.put(:timeout, timeout)
      |> Keyword.put(:request_id, request_id)

    prompt_length = String.length(prompt)
    start_time = System.monotonic_time()

    # Set logger metadata for this dispatch
    Logger.metadata(request_id: request_id, model: model)

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
          {:error, reason} -> {:error, reason}
        end
      rescue
        error ->
          Logger.error("Task execution failed",
            request_id: request_id,
            model: model,
            error: inspect(error)
          )

          {:error, "Task execution failed: #{inspect(error)}"}
      catch
        :exit, {:timeout, _} ->
          Logger.warning("Request timeout",
            request_id: request_id,
            model: model,
            timeout_ms: timeout
          )

          {:error, "Request timeout after #{timeout}ms"}

        :exit, reason ->
          Logger.error("Task exit",
            request_id: request_id,
            model: model,
            reason: inspect(reason)
          )

          {:error, "Task exit: #{inspect(reason)}"}
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
end
