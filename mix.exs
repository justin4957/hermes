defmodule Hermes.MixProject do
  use Mix.Project

  def project do
    [
      app: :hermes,
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      mod: {Hermes.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp deps do
    [
      {:plug_cowboy, "~> 2.7"},
      {:finch, "~> 0.16"},
      {:jason, "~> 1.4"}
    ]
  end
end