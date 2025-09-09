defmodule Hermes.Dispatcher do
  @moduledoc """
  Dispatcher handles routing LLM requests to async workers with timeout and error handling.
  """

  def dispatch(model, prompt, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    
    try do
      task = Task.Supervisor.async_nolink(Hermes.TaskSupervisor, fn ->
        Hermes.Ollama.generate(model, prompt, timeout: timeout)
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