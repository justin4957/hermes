import Config

# Development environment configuration
# These values can be overridden with environment variables

config :hermes, :http, port: 4020

config :hermes, :ollama,
  base_url: "http://localhost:11434",
  timeout: 60_000

# Enable verbose logging in development with metadata
config :logger, :console,
  level: :debug,
  format: "$time $metadata[$level] $message\n",
  metadata: [
    :request_id,
    :model,
    :method,
    :path,
    :status,
    :status_code,
    :duration_ms,
    :http_status,
    :url,
    :timeout,
    :timeout_ms,
    :reason,
    :error,
    :error_type,
    :response_length,
    :prompt_length,
    :ollama_response,
    :current,
    :max,
    :pid
  ]
