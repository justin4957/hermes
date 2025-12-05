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

  The HTTP server port can be configured in `config/config.exs`:

      config :hermes, :http,
        port: 4020
  """

  use Application

  @doc """
  Starts the Hermes application and its supervision tree.

  Called automatically by the OTP framework when the application starts.
  Initializes the HTTP server on port 4020 and sets up supervised processes.

  ## Parameters

    * `_type` - Application start type (unused)
    * `_args` - Application start arguments (unused)

  ## Returns

    * `{:ok, pid}` - Success with supervisor PID
    * `{:error, reason}` - Failure with error reason
  """
  @spec start(any(), any()) :: {:ok, pid()} | {:error, any()}
  def start(_type, _args) do
    children = [
      {Finch, name: Hermes.Finch},
      Hermes.Supervisor,
      {Plug.Cowboy, scheme: :http, plug: Hermes.Router, options: [port: 4020]}
    ]

    opts = [strategy: :one_for_one, name: Hermes.AppSupervisor]
    Supervisor.start_link(children, opts)
  end
end
