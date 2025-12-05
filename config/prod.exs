import Config

# Production environment configuration
config :hermes, :http, port: {:system, "PORT", "4020"}

config :hermes, :ollama,
  base_url: {:system, "OLLAMA_URL", "http://localhost:11434"},
  timeout: 30_000

# Minimal logging in production
config :logger, :console,
  level: :info,
  format: "$time [$level] $message\n"
