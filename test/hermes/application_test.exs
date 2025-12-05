defmodule Hermes.ApplicationTest do
  use ExUnit.Case

  describe "application startup" do
    test "application is started" do
      # The application should already be running in tests
      assert Application.started_applications()
             |> Enum.any?(fn {app, _, _} -> app == :hermes end)
    end

    test "Hermes.Finch is running" do
      # Verify the Finch HTTP client is available
      assert Process.whereis(Hermes.Finch) != nil
    end

    test "Hermes.TaskSupervisor is running" do
      # Verify the task supervisor is available
      assert Process.whereis(Hermes.TaskSupervisor) != nil
    end

    test "can spawn tasks through TaskSupervisor" do
      task =
        Task.Supervisor.async_nolink(Hermes.TaskSupervisor, fn ->
          1 + 1
        end)

      assert Task.await(task) == 2
    end
  end
end
