defmodule Hermes.ConfigTest do
  use ExUnit.Case, async: false

  alias Hermes.Config
  alias Hermes.Error.ModelNotConfiguredError

  # These tests need to run synchronously due to environment variable manipulation
  # and application config changes

  describe "http_port/0" do
    test "returns configured port when no env var set" do
      # Clean up any existing PORT env var
      original_port = System.get_env("PORT")
      System.delete_env("PORT")

      try do
        port = Config.http_port()
        assert is_integer(port)
        assert port > 0
      after
        if original_port, do: System.put_env("PORT", original_port)
      end
    end

    test "returns PORT env var when set" do
      original_port = System.get_env("PORT")
      System.put_env("PORT", "8080")

      try do
        assert Config.http_port() == 8080
      after
        if original_port do
          System.put_env("PORT", original_port)
        else
          System.delete_env("PORT")
        end
      end
    end
  end

  describe "ollama_url/0" do
    test "returns configured URL when no env var set" do
      original_url = System.get_env("OLLAMA_URL")
      System.delete_env("OLLAMA_URL")

      try do
        url = Config.ollama_url()
        assert is_binary(url)
        assert String.starts_with?(url, "http")
      after
        if original_url, do: System.put_env("OLLAMA_URL", original_url)
      end
    end

    test "returns OLLAMA_URL env var when set" do
      original_url = System.get_env("OLLAMA_URL")
      System.put_env("OLLAMA_URL", "http://custom:11434")

      try do
        assert Config.ollama_url() == "http://custom:11434"
      after
        if original_url do
          System.put_env("OLLAMA_URL", original_url)
        else
          System.delete_env("OLLAMA_URL")
        end
      end
    end
  end

  describe "ollama_timeout/0" do
    test "returns configured timeout when no env var set" do
      original_timeout = System.get_env("OLLAMA_TIMEOUT")
      System.delete_env("OLLAMA_TIMEOUT")

      try do
        timeout = Config.ollama_timeout()
        assert is_integer(timeout)
        assert timeout > 0
      after
        if original_timeout, do: System.put_env("OLLAMA_TIMEOUT", original_timeout)
      end
    end

    test "returns OLLAMA_TIMEOUT env var when set" do
      original_timeout = System.get_env("OLLAMA_TIMEOUT")
      System.put_env("OLLAMA_TIMEOUT", "60000")

      try do
        assert Config.ollama_timeout() == 60_000
      after
        if original_timeout do
          System.put_env("OLLAMA_TIMEOUT", original_timeout)
        else
          System.delete_env("OLLAMA_TIMEOUT")
        end
      end
    end
  end

  describe "model_config/1" do
    test "returns config for known model as string" do
      config = Config.model_config("gemma")
      assert is_map(config)
      assert Map.has_key?(config, :timeout)
    end

    test "returns config for known model as atom" do
      config = Config.model_config(:gemma)
      assert is_map(config)
      assert Map.has_key?(config, :timeout)
    end

    test "returns empty map for unknown model" do
      config = Config.model_config("unknown_model_xyz")
      assert config == %{}
    end
  end

  describe "model_timeout/1" do
    test "returns model-specific timeout for configured model" do
      # llama3 has a longer timeout configured
      timeout = Config.model_timeout("llama3")
      assert is_integer(timeout)
      assert timeout > 0
    end

    test "returns default timeout for unconfigured model" do
      timeout = Config.model_timeout("unknown_model_xyz")
      assert timeout == Config.ollama_timeout()
    end
  end

  describe "model_max_concurrency/1" do
    test "returns max_concurrency for configured model" do
      concurrency = Config.model_max_concurrency("gemma")
      assert is_integer(concurrency)
      assert concurrency > 0
    end

    test "returns nil for unconfigured model" do
      concurrency = Config.model_max_concurrency("unknown_model_xyz")
      assert concurrency == nil
    end
  end

  describe "all/0" do
    test "returns complete configuration map" do
      config = Config.all()

      assert is_map(config)
      assert Map.has_key?(config, :http)
      assert Map.has_key?(config, :ollama)
      assert Map.has_key?(config, :models)

      assert is_map(config.http)
      assert Map.has_key?(config.http, :port)

      assert is_map(config.ollama)
      assert Map.has_key?(config.ollama, :base_url)
      assert Map.has_key?(config.ollama, :timeout)
    end
  end

  describe "configured_models/0" do
    test "returns list of configured model atoms" do
      models = Config.configured_models()

      assert is_list(models)
      assert :gemma in models
      assert :llama3 in models
      assert :mistral in models
    end

    test "does not include unconfigured models" do
      models = Config.configured_models()

      refute :unknown in models
      refute :gpt4 in models
    end
  end

  describe "model_configured?/1" do
    test "returns true for configured models as string" do
      assert Config.model_configured?("gemma")
      assert Config.model_configured?("llama3")
      assert Config.model_configured?("mistral")
    end

    test "returns true for configured models as atom" do
      assert Config.model_configured?(:gemma)
      assert Config.model_configured?(:llama3)
      assert Config.model_configured?(:mistral)
    end

    test "returns false for unconfigured models" do
      refute Config.model_configured?("unknown")
      refute Config.model_configured?(:unknown)
      refute Config.model_configured?("gpt4")
      refute Config.model_configured?(:gpt4)
    end
  end

  describe "validate_model/1" do
    test "returns :ok for configured models" do
      assert :ok = Config.validate_model("gemma")
      assert :ok = Config.validate_model(:gemma)
      assert :ok = Config.validate_model("llama3")
      assert :ok = Config.validate_model(:llama3)
    end

    test "returns error tuple for unconfigured models" do
      assert {:error, %ModelNotConfiguredError{model: "unknown"}} =
               Config.validate_model("unknown")

      assert {:error, %ModelNotConfiguredError{model: "gpt4"}} =
               Config.validate_model("gpt4")
    end

    test "error includes list of available models" do
      {:error, %ModelNotConfiguredError{available_models: models}} =
        Config.validate_model("unknown")

      assert is_list(models)
      assert :gemma in models
      assert :llama3 in models
    end

    test "error message includes available models" do
      {:error, %ModelNotConfiguredError{message: message}} =
        Config.validate_model("unknown")

      assert message =~ "unknown"
      assert message =~ "not configured"
      assert message =~ "gemma"
    end
  end

  describe "validate_config/0" do
    test "returns :ok for valid configuration" do
      # The test environment has valid config
      assert :ok = Config.validate_config()
    end
  end
end
