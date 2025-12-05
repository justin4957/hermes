defmodule Hermes.Dispatcher do
  @moduledoc """
  Request dispatcher with async task supervision and timeout handling.

  The Dispatcher module acts as a coordination layer between the HTTP router
  and the Ollama client. It manages async task execution using a supervised
  task supervisor, providing fault tolerance and timeout guarantees.

  ## Responsibility

  - Spawns supervised async tasks for LLM requests
  - Enforces timeout constraints on long-running operations
  - Handles task failures and exits gracefully
  - Provides consistent error reporting

  ## Design

  Each request is processed in an isolated supervised task, ensuring that:
  1. Failures don't crash the main application
  2. Timeouts are reliably enforced
  3. Resources are properly cleaned up
  4. Multiple concurrent requests can be processed safely

  ## Examples

      # Dispatch with default timeout
      {:ok, response} = Hermes.Dispatcher.dispatch("gemma", "Hello")

      # Dispatch with custom timeout
      {:ok, response} = Hermes.Dispatcher.dispatch("llama3", "Long prompt...", timeout: 60_000)

      # Handle timeout
      case Hermes.Dispatcher.dispatch("gemma", "test", timeout: 1) do
        {:ok, _} -> :success
        {:error, "Request timeout after 1ms"} -> :timeout
      end
  """

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
    timeout = Keyword.get(opts, :timeout, 30_000)
    task_supervisor = Keyword.get(opts, :task_supervisor, Hermes.TaskSupervisor)
    ollama_module = Keyword.get(opts, :ollama_module, Hermes.Ollama)
    ollama_opts = Keyword.drop(opts, [:task_supervisor, :ollama_module])

    try do
      task =
        Task.Supervisor.async_nolink(task_supervisor, fn ->
          ollama_module.generate(model, prompt, ollama_opts)
        end)

      case Task.await(task, timeout + 1_000) do
        {:ok, response} -> {:ok, response}
        {:error, reason} -> {:error, reason}
      end
    rescue
      error ->
        {:error, "Task execution failed: #{inspect(error)}"}
    catch
      :exit, {:timeout, _} ->
        {:error, "Request timeout after #{timeout}ms"}

      :exit, reason ->
        {:error, "Task exit: #{inspect(reason)}"}
    end
  end
end
