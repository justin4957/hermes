defmodule Hermes.Application do
  use Application

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