import Config

# Test environment configuration
config :hermes, :http, port: 4021

config :hermes, :ollama,
  base_url: "http://localhost:11434",
  timeout: 10_000

# Configure test models with shorter timeouts
config :hermes, :models,
  gemma: %{max_concurrency: 2, memory_cost: :medium, timeout: 5_000},
  llama3: %{max_concurrency: 1, memory_cost: :high, timeout: 10_000},
  mistral: %{max_concurrency: 2, memory_cost: :medium, timeout: 5_000}

# Print only warnings and errors during test
config :logger, level: :warning
