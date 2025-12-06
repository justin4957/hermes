defmodule Hermes.Error do
  @moduledoc """
  Structured error types for the Hermes application.

  This module defines typed error structs that provide consistent error handling
  across all modules. Each error type maps to a specific HTTP status code and
  includes a user-friendly message.

  ## Error Types

  | Error Type | HTTP Status | Description |
  |------------|-------------|-------------|
  | `ValidationError` | 400 | Invalid request parameters |
  | `ModelNotConfiguredError` | 404 | Model not in Hermes config |
  | `ModelNotFoundError` | 404 | Model not found in Ollama |
  | `ConcurrencyLimitError` | 429 | Model at max concurrency |
  | `TimeoutError` | 408 | Request exceeded timeout |
  | `InternalError` | 500 | Internal server error |
  | `OllamaError` | 502 | Upstream Ollama service error |
  | `ConnectionError` | 503 | Cannot connect to Ollama |

  ## Usage

      case Hermes.Dispatcher.dispatch("gemma", "Hello") do
        {:ok, response} -> handle_success(response)
        {:error, %Hermes.Error.TimeoutError{} = error} -> handle_timeout(error)
        {:error, %Hermes.Error.ModelNotFoundError{} = error} -> handle_not_found(error)
        {:error, error} -> handle_generic_error(error)
      end

  ## HTTP Status Code Mapping

      status_code = Hermes.Error.http_status(error)
      message = Hermes.Error.message(error)
  """

  @type error ::
          Hermes.Error.ValidationError.t()
          | Hermes.Error.ModelNotConfiguredError.t()
          | Hermes.Error.ModelNotFoundError.t()
          | Hermes.Error.ConcurrencyLimitError.t()
          | Hermes.Error.TimeoutError.t()
          | Hermes.Error.OllamaError.t()
          | Hermes.Error.InternalError.t()
          | Hermes.Error.ConnectionError.t()

  defmodule ValidationError do
    @moduledoc """
    Error for invalid request parameters (HTTP 400).

    Raised when the request contains invalid or missing required fields.
    """

    @type t :: %__MODULE__{
            message: String.t(),
            field: String.t() | nil,
            details: map() | nil
          }

    defstruct [:message, :field, :details]

    @doc "Creates a new ValidationError"
    @spec new(String.t(), keyword()) :: t()
    def new(message, opts \\ []) do
      %__MODULE__{
        message: message,
        field: Keyword.get(opts, :field),
        details: Keyword.get(opts, :details)
      }
    end
  end

  defmodule ModelNotConfiguredError do
    @moduledoc """
    Error when the requested model is not configured in Hermes (HTTP 404).

    Raised when a model name is not in the configured models list.
    This is different from ModelNotFoundError which indicates Ollama
    doesn't have the model.
    """

    @type t :: %__MODULE__{
            message: String.t(),
            model: String.t(),
            available_models: [atom()]
          }

    defstruct [:message, :model, :available_models]

    @doc "Creates a new ModelNotConfiguredError"
    @spec new(String.t(), [atom()]) :: t()
    def new(model, available_models \\ []) do
      available_str =
        case available_models do
          [] -> ""
          models -> " Available models: #{Enum.map_join(models, ", ", &Atom.to_string/1)}"
        end

      %__MODULE__{
        message: "Model '#{model}' is not configured.#{available_str}",
        model: model,
        available_models: available_models
      }
    end
  end

  defmodule ModelNotFoundError do
    @moduledoc """
    Error when the requested model is not available in Ollama (HTTP 404).

    Raised when Ollama returns a 404 for the specified model.
    """

    @type t :: %__MODULE__{
            message: String.t(),
            model: String.t()
          }

    defstruct [:message, :model]

    @doc "Creates a new ModelNotFoundError"
    @spec new(String.t()) :: t()
    def new(model) do
      %__MODULE__{
        message: "Model '#{model}' not found. Ensure it is pulled in Ollama.",
        model: model
      }
    end
  end

  defmodule ConcurrencyLimitError do
    @moduledoc """
    Error when the model has reached its maximum concurrent requests (HTTP 429).

    Raised when the configured max_concurrency limit for a model is reached.
    """

    @type t :: %__MODULE__{
            message: String.t(),
            model: String.t(),
            max_concurrency: non_neg_integer(),
            current_count: non_neg_integer()
          }

    defstruct [:message, :model, :max_concurrency, :current_count]

    @doc "Creates a new ConcurrencyLimitError"
    @spec new(String.t(), non_neg_integer(), non_neg_integer()) :: t()
    def new(model, max_concurrency, current_count) do
      %__MODULE__{
        message:
          "Model '#{model}' is at capacity (#{current_count}/#{max_concurrency} concurrent requests). Please retry later.",
        model: model,
        max_concurrency: max_concurrency,
        current_count: current_count
      }
    end
  end

  defmodule TimeoutError do
    @moduledoc """
    Error when the request exceeds the configured timeout (HTTP 408).

    Raised when the LLM generation takes longer than the allowed timeout.
    """

    @type t :: %__MODULE__{
            message: String.t(),
            timeout_ms: non_neg_integer()
          }

    defstruct [:message, :timeout_ms]

    @doc "Creates a new TimeoutError"
    @spec new(non_neg_integer()) :: t()
    def new(timeout_ms) do
      %__MODULE__{
        message: "Request timed out after #{timeout_ms}ms",
        timeout_ms: timeout_ms
      }
    end
  end

  defmodule OllamaError do
    @moduledoc """
    Error from the upstream Ollama service (HTTP 502).

    Raised when Ollama returns an error response (5xx status codes).
    """

    @type t :: %__MODULE__{
            message: String.t(),
            status_code: non_neg_integer() | nil,
            upstream_error: String.t() | nil
          }

    defstruct [:message, :status_code, :upstream_error]

    @doc "Creates a new OllamaError"
    @spec new(String.t(), keyword()) :: t()
    def new(message, opts \\ []) do
      %__MODULE__{
        message: message,
        status_code: Keyword.get(opts, :status_code),
        upstream_error: Keyword.get(opts, :upstream_error)
      }
    end
  end

  defmodule InternalError do
    @moduledoc """
    Internal server error (HTTP 500).

    Raised for unexpected errors within the application.
    """

    @type t :: %__MODULE__{
            message: String.t(),
            reason: term()
          }

    defstruct [:message, :reason]

    @doc "Creates a new InternalError"
    @spec new(String.t(), term()) :: t()
    def new(message, reason \\ nil) do
      %__MODULE__{
        message: message,
        reason: reason
      }
    end
  end

  defmodule ConnectionError do
    @moduledoc """
    Error when unable to connect to Ollama (HTTP 503).

    Raised when the connection to the Ollama service fails.
    """

    @type t :: %__MODULE__{
            message: String.t(),
            url: String.t() | nil,
            reason: term()
          }

    defstruct [:message, :url, :reason]

    @doc "Creates a new ConnectionError"
    @spec new(String.t(), keyword()) :: t()
    def new(message, opts \\ []) do
      %__MODULE__{
        message: message,
        url: Keyword.get(opts, :url),
        reason: Keyword.get(opts, :reason)
      }
    end
  end

  # Protocol for getting HTTP status codes from errors

  @doc """
  Returns the HTTP status code for an error.

  ## Examples

      iex> Hermes.Error.http_status(%Hermes.Error.ValidationError{message: "test"})
      400

      iex> Hermes.Error.http_status(%Hermes.Error.TimeoutError{message: "test", timeout_ms: 1000})
      408
  """
  @spec http_status(error()) :: non_neg_integer()
  def http_status(%ValidationError{}), do: 400
  def http_status(%ModelNotConfiguredError{}), do: 404
  def http_status(%ModelNotFoundError{}), do: 404
  def http_status(%ConcurrencyLimitError{}), do: 429
  def http_status(%TimeoutError{}), do: 408
  def http_status(%InternalError{}), do: 500
  def http_status(%OllamaError{}), do: 502
  def http_status(%ConnectionError{}), do: 503
  def http_status(_), do: 500

  @doc """
  Returns the error message.

  ## Examples

      iex> error = %Hermes.Error.ValidationError{message: "Missing prompt"}
      iex> Hermes.Error.message(error)
      "Missing prompt"
  """
  @spec message(error()) :: String.t()
  def message(%{message: message}) when is_binary(message), do: message
  def message(_), do: "An unexpected error occurred"

  @doc """
  Returns the error type as an atom.

  ## Examples

      iex> Hermes.Error.type(%Hermes.Error.TimeoutError{message: "test", timeout_ms: 1000})
      :timeout
  """
  @spec type(error()) :: atom()
  def type(%ValidationError{}), do: :validation_error
  def type(%ModelNotConfiguredError{}), do: :model_not_configured
  def type(%ModelNotFoundError{}), do: :model_not_found
  def type(%ConcurrencyLimitError{}), do: :concurrency_limit
  def type(%TimeoutError{}), do: :timeout
  def type(%InternalError{}), do: :internal_error
  def type(%OllamaError{}), do: :ollama_error
  def type(%ConnectionError{}), do: :connection_error
  def type(_), do: :unknown_error

  @doc """
  Converts an error to a JSON-serializable map.

  ## Examples

      iex> error = Hermes.Error.TimeoutError.new(5000)
      iex> Hermes.Error.to_map(error)
      %{error: "Request timed out after 5000ms", type: "timeout", timeout_ms: 5000}
  """
  @spec to_map(error()) :: map()
  def to_map(%ValidationError{message: msg, field: field}) do
    base = %{error: msg, type: "validation_error"}
    if field, do: Map.put(base, :field, field), else: base
  end

  def to_map(%ModelNotConfiguredError{message: msg, model: model, available_models: models}) do
    base = %{error: msg, type: "model_not_configured", model: model}

    if models && models != [] do
      Map.put(base, :available_models, Enum.map(models, &Atom.to_string/1))
    else
      base
    end
  end

  def to_map(%ModelNotFoundError{message: msg, model: model}) do
    %{error: msg, type: "model_not_found", model: model}
  end

  def to_map(%ConcurrencyLimitError{
        message: msg,
        model: model,
        max_concurrency: max,
        current_count: current
      }) do
    %{error: msg, type: "concurrency_limit", model: model, max_concurrency: max, current: current}
  end

  def to_map(%TimeoutError{message: msg, timeout_ms: timeout}) do
    %{error: msg, type: "timeout", timeout_ms: timeout}
  end

  def to_map(%OllamaError{message: msg, status_code: status}) do
    base = %{error: msg, type: "ollama_error"}
    if status, do: Map.put(base, :upstream_status, status), else: base
  end

  def to_map(%InternalError{message: msg}) do
    %{error: msg, type: "internal_error"}
  end

  def to_map(%ConnectionError{message: msg, url: url}) do
    base = %{error: msg, type: "connection_error"}
    if url, do: Map.put(base, :url, url), else: base
  end

  def to_map(error) when is_binary(error) do
    %{error: error, type: "unknown_error"}
  end

  def to_map(_) do
    %{error: "An unexpected error occurred", type: "unknown_error"}
  end

  @doc """
  Wraps a legacy string error into a structured error type.

  Attempts to parse the error string and convert it to an appropriate
  error struct. Falls back to InternalError for unrecognized patterns.

  ## Examples

      iex> Hermes.Error.from_string("HTTP 404: model not found", model: "gemma")
      %Hermes.Error.ModelNotFoundError{message: "Model 'gemma' not found. Ensure it is pulled in Ollama.", model: "gemma"}

      iex> Hermes.Error.from_string("Request timeout after 5000ms")
      %Hermes.Error.TimeoutError{message: "Request timed out after 5000ms", timeout_ms: 5000}
  """
  @spec from_string(String.t(), keyword()) :: error()
  def from_string(error_string, opts \\ [])

  def from_string("HTTP 404" <> _, opts) do
    model = Keyword.get(opts, :model, "unknown")
    ModelNotFoundError.new(model)
  end

  def from_string("Request timeout after " <> rest, _opts) do
    timeout =
      case Regex.run(~r/(\d+)ms/, rest) do
        [_, ms] -> String.to_integer(ms)
        _ -> 0
      end

    TimeoutError.new(timeout)
  end

  def from_string("HTTP 5" <> _ = msg, _opts) do
    status_code =
      case Regex.run(~r/HTTP (\d+)/, msg) do
        [_, code] -> String.to_integer(code)
        _ -> nil
      end

    OllamaError.new("Ollama service error", status_code: status_code, upstream_error: msg)
  end

  def from_string("Request failed: " <> reason, opts) do
    cond do
      String.contains?(reason, "connection") or String.contains?(reason, "refused") ->
        ConnectionError.new("Cannot connect to Ollama service",
          url: Keyword.get(opts, :url),
          reason: reason
        )

      String.contains?(reason, "timeout") ->
        TimeoutError.new(Keyword.get(opts, :timeout, 0))

      true ->
        InternalError.new("Request failed", reason)
    end
  end

  def from_string("Task execution failed: " <> reason, _opts) do
    InternalError.new("Internal processing error", reason)
  end

  def from_string("Task exit: " <> reason, _opts) do
    InternalError.new("Task terminated unexpectedly", reason)
  end

  def from_string(error_string, _opts) when is_binary(error_string) do
    InternalError.new(error_string)
  end
end
