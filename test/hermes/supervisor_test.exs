defmodule Hermes.SupervisorTest do
  use ExUnit.Case

  alias Hermes.Supervisor, as: HermesSupervisor

  describe "start_link/1" do
    test "starts the supervisor successfully" do
      # The supervisor is already started as part of the application
      # Verify it's running
      assert Process.whereis(HermesSupervisor) != nil
    end

    test "can start a separate supervisor instance" do
      # Start a new supervisor with a different name for testing
      {:ok, pid} =
        Supervisor.start_link(
          [{Task.Supervisor, name: TestTaskSupervisor, strategy: :one_for_one}],
          strategy: :one_for_one,
          name: TestHermesSupervisor
        )

      assert is_pid(pid)
      assert Process.alive?(pid)

      # Clean up
      Supervisor.stop(pid)
    end
  end

  describe "Task.Supervisor integration" do
    test "spawns async tasks correctly" do
      task =
        Task.Supervisor.async_nolink(Hermes.TaskSupervisor, fn ->
          Process.sleep(10)
          :completed
        end)

      result = Task.await(task, 5000)
      assert result == :completed
    end

    test "handles task failures gracefully" do
      task =
        Task.Supervisor.async_nolink(Hermes.TaskSupervisor, fn ->
          raise "Test error"
        end)

      # The task will exit with an error, but shouldn't crash the supervisor
      assert catch_exit(Task.await(task, 1000))

      # Supervisor should still be alive
      assert Process.alive?(Process.whereis(Hermes.TaskSupervisor))
    end

    test "handles multiple concurrent tasks" do
      tasks =
        for i <- 1..10 do
          Task.Supervisor.async_nolink(Hermes.TaskSupervisor, fn ->
            Process.sleep(5)
            i * 2
          end)
        end

      results = Task.await_many(tasks, 5000)
      expected = Enum.map(1..10, &(&1 * 2))

      assert results == expected
    end

    test "task timeout doesn't affect supervisor" do
      task =
        Task.Supervisor.async_nolink(Hermes.TaskSupervisor, fn ->
          Process.sleep(1000)
          :never_reached
        end)

      # This will timeout
      catch_exit(Task.await(task, 50))

      # Supervisor should still be responsive
      new_task =
        Task.Supervisor.async_nolink(Hermes.TaskSupervisor, fn ->
          :quick_response
        end)

      assert Task.await(new_task, 1000) == :quick_response
    end
  end

  describe "supervision tree" do
    test "child spec is correct" do
      # Verify the child spec returns the expected format
      child_spec = HermesSupervisor.child_spec([])

      assert child_spec.id == HermesSupervisor
      assert child_spec.start == {HermesSupervisor, :start_link, [[]]}
    end
  end
end
