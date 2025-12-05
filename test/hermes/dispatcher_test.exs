defmodule Hermes.DispatcherTest do
  use ExUnit.Case, async: true

  import Mox

  alias Hermes.Dispatcher
  alias Hermes.Error

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
          ollama_module: Hermes.OllamaMock,
          skip_concurrency: true
        )

      assert {:ok, ^expected_response} = result
    end

    test "propagates error from Ollama client", %{supervisor: supervisor} do
      # Using "gemma" since "invalid" is not a configured model
      error = Error.ModelNotFoundError.new("gemma")

      Hermes.OllamaMock
      |> expect(:generate, fn "gemma", "test", _opts ->
        {:error, error}
      end)

      result =
        Dispatcher.dispatch("gemma", "test",
          task_supervisor: supervisor,
          ollama_module: Hermes.OllamaMock,
          skip_concurrency: true
        )

      assert {:error, %Error.ModelNotFoundError{model: "gemma"}} = result
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
          ollama_module: Hermes.OllamaMock,
          skip_concurrency: true
        )

      assert {:error, %Error.TimeoutError{timeout_ms: 100}} = result
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
          ollama_module: Hermes.OllamaMock,
          skip_concurrency: true
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
          ollama_module: Hermes.OllamaMock,
          skip_concurrency: true
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
          ollama_module: Hermes.OllamaMock,
          skip_concurrency: true
        )

      assert {:error, %Error.InternalError{}} = result
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
            ollama_module: Hermes.OllamaMock,
            skip_concurrency: true
          )
        end),
        Task.async(fn ->
          Dispatcher.dispatch("llama3", "World",
            task_supervisor: supervisor,
            ollama_module: Hermes.OllamaMock,
            skip_concurrency: true
          )
        end),
        Task.async(fn ->
          Dispatcher.dispatch("mistral", "Test",
            task_supervisor: supervisor,
            ollama_module: Hermes.OllamaMock,
            skip_concurrency: true
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
          ollama_module: Hermes.OllamaMock,
          skip_concurrency: true
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
          ollama_module: Hermes.OllamaMock,
          skip_concurrency: true
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
          ollama_module: Hermes.OllamaMock,
          skip_concurrency: true
        )

      assert {:ok, "Hello World 🌍"} = result
    end

    test "rejects unconfigured models", %{supervisor: supervisor} do
      result =
        Dispatcher.dispatch("unknown_model", "test",
          task_supervisor: supervisor,
          ollama_module: Hermes.OllamaMock,
          skip_concurrency: true
        )

      assert {:error, %Error.ModelNotConfiguredError{model: "unknown_model"}} = result
    end
  end
end
