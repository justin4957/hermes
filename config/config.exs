import Config

# HTTP server configuration
config :hermes, :http,
  port: 4020,
  host: "localhost"

# Ollama configuration
config :hermes, :ollama,
  base_url: "http://localhost:11434",
  timeout: 30_000

# Model configuration with resource limits
config :hermes, :models,
  gemma: %{max_concurrency: 2, memory_cost: :medium, timeout: 30_000},
  llama3: %{max_concurrency: 1, memory_cost: :high, timeout: 45_000},
  mistral: %{max_concurrency: 2, memory_cost: :medium, timeout: 30_000}

# Task supervisor configuration
config :hermes, :task_supervisor,
  max_children: 10,
  max_seconds: 3600,
  max_restarts: 3

# Import environment specific config files
import_config "#{config_env()}.exs"
