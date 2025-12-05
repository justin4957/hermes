defmodule Hermes.PropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  import Mox

  alias Hermes.Dispatcher

  setup :verify_on_exit!

  setup do
    supervisor_name = :"TestTaskSupervisor_#{System.unique_integer([:positive])}"
    start_supervised!({Task.Supervisor, name: supervisor_name})
    {:ok, supervisor: supervisor_name}
  end

  describe "Dispatcher property tests" do
    property "handles configured model names", %{supervisor: supervisor} do
      check all(model <- configured_model_generator()) do
        Hermes.OllamaMock
        |> stub(:generate, fn _model, _prompt, _opts ->
          {:ok, "response"}
        end)

        result =
          Dispatcher.dispatch(model, "test prompt",
            task_supervisor: supervisor,
            ollama_module: Hermes.OllamaMock,
            skip_concurrency: true
          )

        assert {:ok, "response"} = result
      end
    end

    property "rejects unconfigured model names", %{supervisor: supervisor} do
      check all(model <- unconfigured_model_generator()) do
        Hermes.OllamaMock
        |> stub(:generate, fn _model, _prompt, _opts ->
          {:ok, "response"}
        end)

        result =
          Dispatcher.dispatch(model, "test prompt",
            task_supervisor: supervisor,
            ollama_module: Hermes.OllamaMock,
            skip_concurrency: true
          )

        assert {:error, %Hermes.Error.ModelNotConfiguredError{model: ^model}} = result
      end
    end

    property "handles any valid prompt string", %{supervisor: supervisor} do
      check all(prompt <- prompt_generator()) do
        Hermes.OllamaMock
        |> stub(:generate, fn _model, received_prompt, _opts ->
          assert received_prompt == prompt
          {:ok, "response"}
        end)

        result =
          Dispatcher.dispatch("gemma", prompt,
            task_supervisor: supervisor,
            ollama_module: Hermes.OllamaMock,
            skip_concurrency: true
          )

        assert {:ok, "response"} = result
      end
    end

    property "handles any valid timeout value", %{supervisor: supervisor} do
      check all(timeout <- StreamData.integer(100..60_000)) do
        Hermes.OllamaMock
        |> stub(:generate, fn _model, _prompt, opts ->
          assert Keyword.get(opts, :timeout) == timeout
          {:ok, "response"}
        end)

        result =
          Dispatcher.dispatch("gemma", "test",
            timeout: timeout,
            task_supervisor: supervisor,
            ollama_module: Hermes.OllamaMock,
            skip_concurrency: true
          )

        assert {:ok, "response"} = result
      end
    end

    property "error responses are always {:error, term}", %{supervisor: supervisor} do
      check all(error_message <- StreamData.string(:alphanumeric, min_length: 1)) do
        Hermes.OllamaMock
        |> stub(:generate, fn _model, _prompt, _opts ->
          {:error, error_message}
        end)

        result =
          Dispatcher.dispatch("gemma", "test",
            task_supervisor: supervisor,
            ollama_module: Hermes.OllamaMock,
            skip_concurrency: true
          )

        assert {:error, ^error_message} = result
      end
    end

    property "success responses preserve the response content", %{supervisor: supervisor} do
      check all(response <- StreamData.string(:printable)) do
        Hermes.OllamaMock
        |> stub(:generate, fn _model, _prompt, _opts ->
          {:ok, response}
        end)

        result =
          Dispatcher.dispatch("gemma", "test",
            task_supervisor: supervisor,
            ollama_module: Hermes.OllamaMock,
            skip_concurrency: true
          )

        assert {:ok, ^response} = result
      end
    end
  end

  describe "JSON encoding/decoding property tests" do
    property "request body is always valid JSON" do
      check all(
              model <- model_name_generator(),
              prompt <- prompt_generator()
            ) do
        body =
          Jason.encode!(%{
            model: model,
            prompt: prompt,
            stream: false
          })

        assert {:ok, decoded} = Jason.decode(body)
        assert decoded["model"] == model
        assert decoded["prompt"] == prompt
        assert decoded["stream"] == false
      end
    end

    property "response body can always be decoded" do
      check all(response <- StreamData.string(:printable)) do
        body = Jason.encode!(%{"response" => response})
        assert {:ok, decoded} = Jason.decode(body)
        assert decoded["response"] == response
      end
    end
  end

  describe "Input validation property tests" do
    property "empty prompts are handled" do
      check all(_model <- model_name_generator()) do
        body = Jason.encode!(%{"prompt" => ""})
        assert {:ok, decoded} = Jason.decode(body)
        assert decoded["prompt"] == ""
      end
    end

    property "prompts with special characters are JSON-safe" do
      check all(
              base <- StreamData.string(:printable, min_length: 1),
              special <- StreamData.member_of(["<", ">", "&", "'", "\"", "\n", "\t"])
            ) do
        prompt = base <> special <> base

        body = Jason.encode!(%{"prompt" => prompt})
        assert {:ok, decoded} = Jason.decode(body)
        assert decoded["prompt"] == prompt
      end
    end
  end

  # Custom generators

  # Generator for configured model names only
  defp configured_model_generator do
    StreamData.member_of(["gemma", "llama3", "mistral", "codellama", "phi"])
  end

  # Generator for unconfigured model names (random alphanumeric that don't match configured models)
  defp unconfigured_model_generator do
    configured = ["gemma", "llama3", "mistral", "codellama", "phi"]

    StreamData.filter(
      StreamData.string(:alphanumeric, min_length: 1, max_length: 50),
      fn model -> model not in configured end
    )
  end

  # Generator for any model name (including random ones for JSON tests)
  defp model_name_generator do
    StreamData.one_of([
      StreamData.constant("gemma"),
      StreamData.constant("llama3"),
      StreamData.constant("mistral"),
      StreamData.constant("codellama"),
      StreamData.constant("phi"),
      StreamData.string(:alphanumeric, min_length: 1, max_length: 50)
    ])
  end

  defp prompt_generator do
    StreamData.one_of([
      StreamData.string(:printable, min_length: 1, max_length: 1000),
      # Simple prompts
      StreamData.constant("Hello, how are you?"),
      StreamData.constant("What is 2 + 2?"),
      # Unicode prompts
      StreamData.constant("你好世界"),
      StreamData.constant("Émojis: 🎉🌍✨"),
      # Multiline prompts
      StreamData.constant("Line 1\nLine 2\nLine 3"),
      # Edge cases
      StreamData.constant(""),
      StreamData.constant(" "),
      StreamData.constant("   \t\n   ")
    ])
  end
end
