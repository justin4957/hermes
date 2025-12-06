defmodule Hermes.Application do
  @moduledoc """
  Application supervisor and startup logic for Hermes.

  This module implements the OTP Application behavior and defines the supervision
  tree for the Hermes service. It starts all necessary child processes including
  the HTTP server, Finch HTTP client, and task supervisor.

  ## Supervision Tree

  ```
  Hermes.Application (one_for_one)
  ├── Finch (HTTP client pool)
  ├── Hermes.Supervisor (task supervisor wrapper)
  └── Plug.Cowboy (HTTP server)
  ```

  ## Configuration

  The HTTP server port can be configured via:

  1. Environment variable: `PORT=4020`
  2. Application config in `config/config.exs`:

      config :hermes, :http,
        port: 4020

  Environment variables take precedence over config file settings.
  """

  use Application

  alias Hermes.Config

  @doc """
  Starts the Hermes application and its supervision tree.

  Called automatically by the OTP framework when the application starts.
  Initializes the HTTP server on the configured port and sets up supervised processes.

  The port is determined by `Hermes.Config.http_port/0`, which checks:
  1. `PORT` environment variable
  2. Application config (`:hermes, :http, :port`)
  3. Default value of 4020

  ## Parameters

    * `_type` - Application start type (unused)
    * `_args` - Application start arguments (unused)

  ## Returns

    * `{:ok, pid}` - Success with supervisor PID
    * `{:error, reason}` - Failure with error reason
  """
  @spec start(any(), any()) :: {:ok, pid()} | {:error, any()}
  def start(_type, _args) do
    # Validate configuration before starting
    case Config.validate_config() do
      :ok ->
        start_supervised_tree()

      {:error, reason} ->
        {:error, {:config_validation_failed, reason}}
    end
  end

  defp start_supervised_tree do
    port = Config.http_port()

    children = [
      {Finch, name: Hermes.Finch},
      Hermes.Supervisor,
      Hermes.ModelRegistry,
      {Plug.Cowboy, scheme: :http, plug: Hermes.Router, options: [port: port]}
    ]

    opts = [strategy: :one_for_one, name: Hermes.AppSupervisor]
    Supervisor.start_link(children, opts)
  end
end
