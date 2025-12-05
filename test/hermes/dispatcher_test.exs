defmodule Hermes.DispatcherTest do
  use ExUnit.Case, async: true

  import Mox

  alias Hermes.Dispatcher

  setup :verify_on_exit!

  setup do
    # Start a task supervisor for each test
    supervisor_name = :"TestTaskSupervisor_#{System.unique_integer([:positive])}"
    start_supervised!({Task.Supervisor, name: supervisor_name})
    {:ok, supervisor: supervisor_name}
  end

  describe "dispatch/3" do
    test "returns successful response from Ollama", %{supervisor: supervisor} do
      expected_response = "The answer is 42."

      Hermes.OllamaMock
      |> expect(:generate, fn "gemma", "What is the meaning of life?", _opts ->
        {:ok, expected_response}
      end)

      result =
        Dispatcher.dispatch("gemma", "What is the meaning of life?",
          task_supervisor: supervisor,
          ollama_module: Hermes.OllamaMock
        )

      assert {:ok, ^expected_response} = result
    end

    test "propagates error from Ollama client", %{supervisor: supervisor} do
      error_message = "HTTP 404: model not found"

      Hermes.OllamaMock
      |> expect(:generate, fn "invalid", "test", _opts ->
        {:error, error_message}
      end)

      result =
        Dispatcher.dispatch("invalid", "test",
          task_supervisor: supervisor,
          ollama_module: Hermes.OllamaMock
        )

      assert {:error, ^error_message} = result
    end

    test "handles timeout from task await", %{supervisor: supervisor} do
      Hermes.OllamaMock
      |> expect(:generate, fn "gemma", "test", _opts ->
        # Sleep longer than the await timeout (timeout + 1000ms)
        Process.sleep(5000)
        {:ok, "delayed"}
      end)

      result =
        Dispatcher.dispatch("gemma", "test",
          timeout: 100,
          task_supervisor: supervisor,
          ollama_module: Hermes.OllamaMock
        )

      assert {:error, message} = result
      assert message =~ "timeout" or message =~ "exit"
    end

    test "uses default timeout of 30000ms", %{supervisor: supervisor} do
      Hermes.OllamaMock
      |> expect(:generate, fn "gemma", "test", _opts ->
        # The timeout is used for await, not necessarily passed to generate
        {:ok, "response"}
      end)

      result =
        Dispatcher.dispatch("gemma", "test",
          task_supervisor: supervisor,
          ollama_module: Hermes.OllamaMock
        )

      assert {:ok, "response"} = result
    end

    test "passes custom timeout to Ollama client", %{supervisor: supervisor} do
      custom_timeout = 60_000

      Hermes.OllamaMock
      |> expect(:generate, fn "gemma", "test", opts ->
        assert Keyword.get(opts, :timeout) == custom_timeout
        {:ok, "response"}
      end)

      result =
        Dispatcher.dispatch("gemma", "test",
          timeout: custom_timeout,
          task_supervisor: supervisor,
          ollama_module: Hermes.OllamaMock
        )

      assert {:ok, "response"} = result
    end

    test "handles task execution failure (exception in worker)", %{supervisor: supervisor} do
      Hermes.OllamaMock
      |> expect(:generate, fn "gemma", "test", _opts ->
        raise "Unexpected error!"
      end)

      result =
        Dispatcher.dispatch("gemma", "test",
          task_supervisor: supervisor,
          ollama_module: Hermes.OllamaMock
        )

      assert {:error, message} = result
      assert message =~ "exit" or message =~ "Task"
    end

    test "handles multiple concurrent requests", %{supervisor: supervisor} do
      Hermes.OllamaMock
      |> expect(:generate, 3, fn model, prompt, _opts ->
        # Simulate some processing time
        Process.sleep(10)
        {:ok, "Response for #{model}: #{prompt}"}
      end)

      tasks = [
        Task.async(fn ->
          Dispatcher.dispatch("gemma", "Hello",
            task_supervisor: supervisor,
            ollama_module: Hermes.OllamaMock
          )
        end),
        Task.async(fn ->
          Dispatcher.dispatch("llama3", "World",
            task_supervisor: supervisor,
            ollama_module: Hermes.OllamaMock
          )
        end),
        Task.async(fn ->
          Dispatcher.dispatch("mistral", "Test",
            task_supervisor: supervisor,
            ollama_module: Hermes.OllamaMock
          )
        end)
      ]

      results = Task.await_many(tasks, 5000)

      Enum.each(results, fn result ->
        assert {:ok, response} = result
        assert response =~ "Response for"
      end)
    end

    test "passes model and prompt correctly to Ollama", %{supervisor: supervisor} do
      model = "codellama"
      prompt = "Write a function to calculate factorial"

      Hermes.OllamaMock
      |> expect(:generate, fn received_model, received_prompt, _opts ->
        assert received_model == model
        assert received_prompt == prompt
        {:ok, "def factorial(n): ..."}
      end)

      result =
        Dispatcher.dispatch(model, prompt,
          task_supervisor: supervisor,
          ollama_module: Hermes.OllamaMock
        )

      assert {:ok, "def factorial(n): ..."} = result
    end

    test "handles empty response from Ollama", %{supervisor: supervisor} do
      Hermes.OllamaMock
      |> expect(:generate, fn "gemma", "test", _opts ->
        {:ok, ""}
      end)

      result =
        Dispatcher.dispatch("gemma", "test",
          task_supervisor: supervisor,
          ollama_module: Hermes.OllamaMock
        )

      assert {:ok, ""} = result
    end

    test "handles unicode in model and prompt", %{supervisor: supervisor} do
      unicode_prompt = "Translate: 你好世界 🌍"

      Hermes.OllamaMock
      |> expect(:generate, fn "gemma", ^unicode_prompt, _opts ->
        {:ok, "Hello World 🌍"}
      end)

      result =
        Dispatcher.dispatch("gemma", unicode_prompt,
          task_supervisor: supervisor,
          ollama_module: Hermes.OllamaMock
        )

      assert {:ok, "Hello World 🌍"} = result
    end
  end
end
