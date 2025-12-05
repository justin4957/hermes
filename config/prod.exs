import Config

# Production environment configuration
#
# In production, use environment variables to configure:
#   PORT         - HTTP server port (default: 4020)
#   OLLAMA_URL   - Ollama server URL (default: http://localhost:11434)
#   OLLAMA_TIMEOUT - Request timeout in ms (default: 30000)
#
# Example:
#   PORT=8080 OLLAMA_URL=http://ollama:11434 ./hermes start

config :hermes, :http, port: 4020

config :hermes, :ollama,
  base_url: "http://localhost:11434",
  timeout: 30_000

# Structured logging in production with metadata
config :logger, :console,
  level: :info,
  format: "$time $metadata[$level] $message\n",
  metadata: [
    :request_id,
    :model,
    :status,
    :status_code,
    :duration_ms,
    :http_status,
    :error,
    :error_type,
    :response_length,
    :prompt_length,
    :ollama_response
  ]
