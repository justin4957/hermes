import Config

# Test environment configuration
config :hermes, :http,
  port: 4021

config :hermes, :ollama,
  base_url: "http://localhost:11434",
  timeout: 10_000

# Print only warnings and errors during test
config :logger, level: :warning