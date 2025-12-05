defmodule Hermes.Supervisor do
  @moduledoc """
  Supervisor for managing async task execution.

  This supervisor wraps a `Task.Supervisor` that is used for spawning and
  supervising async LLM generation tasks. Using supervised tasks ensures that:

  - Task failures are isolated and don't crash the application
  - Resources are properly cleaned up when tasks complete or fail
  - Task crashes are logged and handled gracefully

  The supervisor uses a `:one_for_one` strategy, meaning if a task crashes,
  only that task is restarted (not all tasks).

  ## Usage

  Tasks are spawned through this supervisor via `Hermes.Dispatcher`:

      Task.Supervisor.async_nolink(Hermes.TaskSupervisor, fn ->
        # LLM generation work
      end)
  """

  use Supervisor

  @doc """
  Starts the supervisor and its task supervisor child.

  ## Parameters

    * `_init_arg` - Initialization arguments (unused)

  ## Returns

    * `{:ok, pid}` - Success with supervisor PID
    * `{:error, reason}` - Failure with error reason
  """
  @spec start_link(any()) :: {:ok, pid()} | {:error, any()}
  def start_link(_init_arg) do
    Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc false
  @spec init(:ok) :: {:ok, {:supervisor.sup_flags(), [:supervisor.child_spec()]}}
  def init(:ok) do
    children = [
      {Task.Supervisor, name: Hermes.TaskSupervisor, strategy: :one_for_one}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
