import Config

# HTTP server configuration
# Can be overridden with PORT environment variable
config :hermes, :http, port: 4020

# Ollama configuration
# Can be overridden with OLLAMA_URL and OLLAMA_TIMEOUT environment variables
config :hermes, :ollama,
  base_url: "http://localhost:11434",
  timeout: 30_000

# Model configuration with resource limits
# Each model can have its own timeout, concurrency, and memory settings
config :hermes, :models,
  gemma: %{max_concurrency: 2, memory_cost: :medium, timeout: 30_000},
  llama3: %{max_concurrency: 1, memory_cost: :high, timeout: 45_000},
  mistral: %{max_concurrency: 2, memory_cost: :medium, timeout: 30_000},
  codellama: %{max_concurrency: 1, memory_cost: :high, timeout: 60_000},
  phi: %{max_concurrency: 3, memory_cost: :low, timeout: 20_000}

# Task supervisor configuration
config :hermes, :task_supervisor,
  max_children: 10,
  max_seconds: 3600,
  max_restarts: 3

# Import environment specific config files
import_config "#{config_env()}.exs"
