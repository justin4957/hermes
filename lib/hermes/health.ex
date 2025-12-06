defmodule Hermes.Health do
  @moduledoc """
  Health check and system status module for Hermes.

  Provides comprehensive health check functionality including:
  - Application uptime tracking
  - Ollama service connectivity verification
  - System resource monitoring
  - Version information

  ## Usage

  The main entry point is `check/0` which returns a complete health status:

      iex> Hermes.Health.check()
      %{
        status: :healthy,
        checks: %{ollama: :ok},
        version: "0.1.0",
        uptime_seconds: 3600,
        ...
      }

  ## Kubernetes Integration

  This module is designed to work with Kubernetes liveness and readiness probes:

  - **Liveness probe**: Use `/v1/status` - returns 200 if application is running
  - **Readiness probe**: Use `/v1/status` - returns 503 if Ollama is unreachable

  Example Kubernetes configuration:

      livenessProbe:
        httpGet:
          path: /v1/status
          port: 4020
        initialDelaySeconds: 5
        periodSeconds: 10

      readinessProbe:
        httpGet:
          path: /v1/status
          port: 4020
        initialDelaySeconds: 5
        periodSeconds: 10
  """

  require Logger

  alias Hermes.Config

  @health_check_timeout 5_000

  @doc """
  Records the application start time.

  Should be called once during application startup to enable uptime tracking.
  Stores the start time in a persistent term for fast access.
  """
  @spec record_start_time() :: :ok
  def record_start_time do
    :persistent_term.put({__MODULE__, :start_time}, System.monotonic_time(:second))
    :ok
  end

  @doc """
  Returns the application uptime in seconds.

  Returns 0 if the start time hasn't been recorded yet.

  ## Examples

      iex> Hermes.Health.uptime_seconds()
      3600
  """
  @spec uptime_seconds() :: non_neg_integer()
  def uptime_seconds do
    case :persistent_term.get({__MODULE__, :start_time}, nil) do
      nil -> 0
      start_time -> System.monotonic_time(:second) - start_time
    end
  end

  @doc """
  Returns the application version from Mix.Project.

  Falls back to "unknown" if version cannot be determined.

  ## Examples

      iex> Hermes.Health.version()
      "0.1.0"
  """
  @spec version() :: String.t()
  def version do
    case :application.get_key(:hermes, :vsn) do
      {:ok, version} -> to_string(version)
      :undefined -> "unknown"
    end
  end

  @doc """
  Checks if the Ollama service is reachable and responding.

  Makes a lightweight request to the Ollama API tags endpoint
  to verify connectivity without loading a model.

  ## Options

    * `:timeout` - Request timeout in milliseconds (default: 5000)
    * `:base_url` - Override Ollama base URL

  ## Returns

    * `:ok` - Ollama is reachable and responding
    * `{:error, reason}` - Ollama is unreachable or returned an error

  ## Examples

      iex> Hermes.Health.check_ollama()
      :ok

      iex> Hermes.Health.check_ollama()
      {:error, :connection_refused}
  """
  @spec check_ollama(keyword()) :: :ok | {:error, atom() | String.t()}
  def check_ollama(opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @health_check_timeout)
    base_url = Keyword.get(opts, :base_url, Config.ollama_url())
    finch_name = Keyword.get(opts, :finch_name, Hermes.Finch)
    url = "#{base_url}/api/tags"

    Logger.debug("Checking Ollama health", url: url, timeout: timeout)

    case Finch.build(:get, url)
         |> Finch.request(finch_name, receive_timeout: timeout) do
      {:ok, %{status: status}} when status in 200..299 ->
        :ok

      {:ok, %{status: status}} ->
        {:error, "unexpected_status_#{status}"}

      {:error, %Mint.TransportError{reason: :timeout}} ->
        {:error, :timeout}

      {:error, %Mint.TransportError{reason: reason}} ->
        {:error, reason}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Performs a comprehensive health check of the application.

  Checks all dependencies and returns a detailed health status.
  The overall status is `:healthy` only if all checks pass.

  ## Options

    * `:skip_ollama` - Skip the Ollama connectivity check (default: false)

  ## Returns

  A map containing:

    * `:status` - Overall health status (`:healthy` or `:unhealthy`)
    * `:checks` - Map of individual check results
    * `:version` - Application version
    * `:uptime_seconds` - Time since application start
    * `:memory` - BEAM VM memory statistics
    * `:schedulers` - Number of online schedulers
    * `:models` - List of configured models

  ## Examples

      iex> Hermes.Health.check()
      %{
        status: :healthy,
        checks: %{ollama: :ok},
        version: "0.1.0",
        uptime_seconds: 3600,
        memory: %{total: 12345678, processes: 4567890, system: 7890123},
        schedulers: 8,
        models: ["gemma", "llama3", "mistral"]
      }
  """
  @spec check(keyword()) :: map()
  def check(opts \\ []) do
    skip_ollama = Keyword.get(opts, :skip_ollama, false)

    # Run checks
    ollama_result =
      if skip_ollama do
        :skipped
      else
        check_ollama(opts)
      end

    checks = %{
      ollama: format_check_result(ollama_result)
    }

    # Determine overall status
    status = determine_overall_status(checks)

    # Gather system info
    memory_info = :erlang.memory()

    %{
      status: status,
      checks: checks,
      version: version(),
      uptime_seconds: uptime_seconds(),
      memory: %{
        total: memory_info[:total],
        processes: memory_info[:processes],
        system: memory_info[:system]
      },
      schedulers: System.schedulers_online(),
      models: Enum.map(Config.configured_models(), &Atom.to_string/1)
    }
  end

  defp format_check_result(:ok), do: :ok
  defp format_check_result(:skipped), do: :skipped
  defp format_check_result({:error, reason}) when is_atom(reason), do: {:error, reason}

  defp format_check_result({:error, reason}) when is_binary(reason),
    do: {:error, String.to_atom(reason)}

  defp determine_overall_status(checks) do
    all_ok =
      Enum.all?(checks, fn
        {_name, :ok} -> true
        {_name, :skipped} -> true
        {_name, _} -> false
      end)

    if all_ok, do: :healthy, else: :unhealthy
  end

  @doc """
  Converts health check result to HTTP status code.

  ## Returns

    * `200` - All checks passed (healthy)
    * `503` - One or more checks failed (unhealthy)

  ## Examples

      iex> Hermes.Health.http_status(%{status: :healthy})
      200

      iex> Hermes.Health.http_status(%{status: :unhealthy})
      503
  """
  @spec http_status(map()) :: 200 | 503
  def http_status(%{status: :healthy}), do: 200
  def http_status(%{status: :unhealthy}), do: 503

  @doc """
  Converts health check result to JSON-serializable map.

  Transforms atoms and error tuples into string representations
  suitable for JSON encoding.

  ## Examples

      iex> Hermes.Health.to_json(%{status: :healthy, checks: %{ollama: :ok}})
      %{status: "healthy", checks: %{ollama: "ok"}}
  """
  @spec to_json(map()) :: map()
  def to_json(health) do
    %{
      status: Atom.to_string(health.status),
      checks: format_checks_for_json(health.checks),
      version: health.version,
      uptime_seconds: health.uptime_seconds,
      memory: health.memory,
      schedulers: health.schedulers,
      models: health.models
    }
  end

  defp format_checks_for_json(checks) do
    Map.new(checks, fn {name, result} ->
      formatted =
        case result do
          :ok -> "ok"
          :skipped -> "skipped"
          {:error, reason} when is_atom(reason) -> "error: #{reason}"
          {:error, reason} -> "error: #{reason}"
        end

      {name, formatted}
    end)
  end
end
