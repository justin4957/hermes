import Config

# Development environment configuration
# These values can be overridden with environment variables

config :hermes, :http, port: 4020

config :hermes, :ollama,
  base_url: "http://localhost:11434",
  timeout: 60_000

# Enable verbose logging in development
config :logger, :console,
  level: :debug,
  format: "$time $metadata[$level] $message\n"
