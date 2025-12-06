defmodule Hermes.Config do
  @moduledoc """
  Configuration helper for Hermes application.

  Provides functions to retrieve configuration values with support for:
  - Environment variable overrides
  - Default values
  - Model-specific configuration

  ## Environment Variables

  The following environment variables are supported:

  | Variable | Description | Default |
  |----------|-------------|---------|
  | `PORT` | HTTP server port | 4020 |
  | `OLLAMA_URL` | Ollama server base URL | http://localhost:11434 |
  | `OLLAMA_TIMEOUT` | Default request timeout (ms) | 30000 |

  ## Configuration Priority

  Values are resolved in the following order (highest to lowest priority):
  1. Environment variables
  2. Environment-specific config (dev.exs, prod.exs, test.exs)
  3. Base config (config.exs)
  4. Default values in code
  """

  alias Hermes.Error.ModelNotConfiguredError

  @default_port 4020
  @default_ollama_url "http://localhost:11434"
  @default_timeout 30_000

  @doc """
  Returns the HTTP server port.

  Reads from the `PORT` environment variable, falling back to application config.

  ## Examples

      iex> Hermes.Config.http_port()
      4020
  """
  @spec http_port() :: non_neg_integer()
  def http_port do
    case System.get_env("PORT") do
      nil -> get_config_value([:http, :port], @default_port)
      port -> String.to_integer(port)
    end
  end

  @doc """
  Returns the Ollama server base URL.

  Reads from the `OLLAMA_URL` environment variable, falling back to application config.

  ## Examples

      iex> Hermes.Config.ollama_url()
      "http://localhost:11434"
  """
  @spec ollama_url() :: String.t()
  def ollama_url do
    case System.get_env("OLLAMA_URL") do
      nil -> get_config_value([:ollama, :base_url], @default_ollama_url)
      url -> url
    end
  end

  @doc """
  Returns the default Ollama request timeout in milliseconds.

  Reads from the `OLLAMA_TIMEOUT` environment variable, falling back to application config.

  ## Examples

      iex> Hermes.Config.ollama_timeout()
      30_000
  """
  @spec ollama_timeout() :: non_neg_integer()
  def ollama_timeout do
    case System.get_env("OLLAMA_TIMEOUT") do
      nil -> get_config_value([:ollama, :timeout], @default_timeout)
      timeout -> String.to_integer(timeout)
    end
  end

  @doc """
  Returns a list of all configured model names as atoms.

  ## Examples

      iex> Hermes.Config.configured_models()
      [:gemma, :llama3, :mistral, :codellama, :phi]
  """
  @spec configured_models() :: [atom()]
  def configured_models do
    models = Application.get_env(:hermes, :models, [])
    extract_model_names(models)
  end

  defp extract_model_names(models) when is_list(models), do: Keyword.keys(models)
  defp extract_model_names(models) when is_map(models), do: Map.keys(models)
  defp extract_model_names(_), do: []

  @doc """
  Checks if a model is configured.

  ## Parameters

    * `model` - Model name as string or atom

  ## Returns

    * `true` if the model is configured, `false` otherwise

  ## Examples

      iex> Hermes.Config.model_configured?("gemma")
      true

      iex> Hermes.Config.model_configured?(:llama3)
      true

      iex> Hermes.Config.model_configured?("unknown")
      false
  """
  @spec model_configured?(String.t() | atom()) :: boolean()
  def model_configured?(model) when is_binary(model) do
    model
    |> String.to_atom()
    |> model_configured?()
  end

  def model_configured?(model) when is_atom(model) do
    model in configured_models()
  end

  @doc """
  Validates that a model is configured and returns the result.

  ## Parameters

    * `model` - Model name as string or atom

  ## Returns

    * `:ok` if the model is configured
    * `{:error, Hermes.Error.ModelNotConfiguredError.t()}` if not configured

  ## Examples

      iex> Hermes.Config.validate_model("gemma")
      :ok

      iex> Hermes.Config.validate_model("unknown")
      {:error, %Hermes.Error.ModelNotConfiguredError{...}}
  """
  @spec validate_model(String.t() | atom()) ::
          :ok | {:error, ModelNotConfiguredError.t()}
  def validate_model(model) do
    if model_configured?(model) do
      :ok
    else
      model_str = if is_atom(model), do: Atom.to_string(model), else: model
      {:error, ModelNotConfiguredError.new(model_str, configured_models())}
    end
  end

  @doc """
  Validates the models configuration at startup.

  Checks that:
  - Models config exists and is not empty
  - Each model has required fields (max_concurrency, timeout)
  - Values are valid types

  ## Returns

    * `:ok` if configuration is valid
    * `{:error, reason}` if configuration is invalid
  """
  @spec validate_config() :: :ok | {:error, String.t()}
  def validate_config do
    models = Application.get_env(:hermes, :models)

    cond do
      is_nil(models) ->
        {:error, "No models configured. Add models to config :hermes, :models"}

      models == [] or models == %{} ->
        {:error, "Models configuration is empty. Add at least one model."}

      true ->
        validate_model_configs(models)
    end
  end

  defp validate_model_configs(models) when is_list(models) do
    Enum.reduce_while(models, :ok, fn {name, config}, :ok ->
      case validate_single_model_config(name, config) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp validate_model_configs(models) when is_map(models) do
    models
    |> Enum.to_list()
    |> validate_model_configs()
  end

  defp validate_single_model_config(name, config) when is_map(config) do
    cond do
      not is_atom(name) ->
        {:error, "Model name must be an atom, got: #{inspect(name)}"}

      not Map.has_key?(config, :max_concurrency) ->
        {:error, "Model #{name} missing :max_concurrency"}

      not is_integer(config.max_concurrency) or config.max_concurrency < 1 ->
        {:error, "Model #{name} :max_concurrency must be a positive integer"}

      Map.has_key?(config, :timeout) and
          (not is_integer(config.timeout) or config.timeout < 1) ->
        {:error, "Model #{name} :timeout must be a positive integer"}

      true ->
        :ok
    end
  end

  defp validate_single_model_config(name, _config) do
    {:error, "Model #{name} config must be a map"}
  end

  @doc """
  Returns the configuration for a specific model.

  Model configuration includes:
  - `:timeout` - Request timeout in milliseconds
  - `:max_concurrency` - Maximum concurrent requests
  - `:memory_cost` - Memory cost category (:low, :medium, :high)

  ## Parameters

    * `model` - Model name as string or atom

  ## Returns

    * Map with model configuration, or empty map if model not configured

  ## Examples

      iex> Hermes.Config.model_config("gemma")
      %{max_concurrency: 2, memory_cost: :medium, timeout: 30_000}

      iex> Hermes.Config.model_config(:llama3)
      %{max_concurrency: 1, memory_cost: :high, timeout: 45_000}

      iex> Hermes.Config.model_config("unknown")
      %{}
  """
  @spec model_config(String.t() | atom()) :: map()
  def model_config(model) when is_binary(model) do
    model
    |> String.to_atom()
    |> model_config()
  end

  def model_config(model) when is_atom(model) do
    models = Application.get_env(:hermes, :models, [])
    get_model_from_config(models, model)
  end

  defp get_model_from_config(models, model) when is_list(models) do
    Keyword.get(models, model, %{})
  end

  defp get_model_from_config(models, model) when is_map(models) do
    Map.get(models, model, %{})
  end

  defp get_model_from_config(_models, _model), do: %{}

  @doc """
  Returns the timeout for a specific model.

  Falls back to the default Ollama timeout if no model-specific timeout is configured.

  ## Parameters

    * `model` - Model name as string or atom

  ## Examples

      iex> Hermes.Config.model_timeout("gemma")
      30_000

      iex> Hermes.Config.model_timeout("llama3")
      45_000

      iex> Hermes.Config.model_timeout("unknown")
      30_000
  """
  @spec model_timeout(String.t() | atom()) :: non_neg_integer()
  def model_timeout(model) do
    config = model_config(model)
    Map.get(config, :timeout, ollama_timeout())
  end

  @doc """
  Returns the max concurrency for a specific model.

  Falls back to nil if no model-specific max_concurrency is configured.

  ## Parameters

    * `model` - Model name as string or atom

  ## Examples

      iex> Hermes.Config.model_max_concurrency("gemma")
      2

      iex> Hermes.Config.model_max_concurrency("unknown")
      nil
  """
  @spec model_max_concurrency(String.t() | atom()) :: non_neg_integer() | nil
  def model_max_concurrency(model) do
    config = model_config(model)
    Map.get(config, :max_concurrency)
  end

  @doc """
  Returns all configuration as a map for debugging/status endpoints.

  ## Examples

      iex> Hermes.Config.all()
      %{
        http: %{port: 4020},
        ollama: %{base_url: "http://localhost:11434", timeout: 30_000},
        models: %{gemma: %{...}, llama3: %{...}}
      }
  """
  @spec all() :: map()
  def all do
    models = Application.get_env(:hermes, :models, [])

    %{
      http: %{
        port: http_port()
      },
      ollama: %{
        base_url: ollama_url(),
        timeout: ollama_timeout()
      },
      models: normalize_models(models)
    }
  end

  defp normalize_models(models) when is_list(models), do: Map.new(models)
  defp normalize_models(models) when is_map(models), do: models
  defp normalize_models(_), do: %{}

  # Private helpers

  defp get_config_value(keys, default) do
    case keys do
      [section, key] ->
        config = Application.get_env(:hermes, section, [])
        get_in_config(config, key, default)

      [key] ->
        Application.get_env(:hermes, key, default)
    end
  end

  defp get_in_config(config, key, default) when is_list(config) do
    Keyword.get(config, key, default)
  end

  defp get_in_config(config, key, default) when is_map(config) do
    Map.get(config, key, default)
  end

  defp get_in_config(_config, _key, default), do: default
end
