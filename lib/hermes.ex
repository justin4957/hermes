defmodule Hermes do
  @moduledoc """
  Hermes - A minimal Elixir sidecar service for Ollama LLM integration.

  Hermes provides a lightweight HTTP API layer on top of Ollama, enabling efficient
  concurrent processing of LLM requests with built-in timeout handling, resource
  management, and fault tolerance.

  ## Features

  - **Concurrent Processing**: Leverages Elixir's actor model to handle multiple
    LLM requests simultaneously without blocking
  - **Multiple Model Support**: Switch between different models (Gemma, Llama3,
    Mistral, etc.) via API endpoints
  - **Resource Management**: Built-in timeout handling and configurable resource limits
  - **HTTP API**: Simple REST endpoints for LLM interaction
  - **Fault Tolerance**: Supervised processes ensure service reliability

  ## Architecture

  The service follows a layered architecture:

  ```
  HTTP Request → Router → Dispatcher → Task Supervisor → Ollama Client
  ```

  1. `Hermes.Router` - Handles HTTP requests and response formatting
  2. `Hermes.Dispatcher` - Manages request dispatch with timeout handling
  3. `Hermes.TaskSupervisor` - Supervises concurrent task execution
  4. `Hermes.Ollama` - HTTP client for Ollama REST API

  ## Configuration

  Configure models and resource limits in `config/config.exs`:

      config :hermes, :models,
        gemma: %{max_concurrency: 2, memory_cost: :medium, timeout: 30_000},
        llama3: %{max_concurrency: 1, memory_cost: :high, timeout: 45_000}

      config :hermes, :ollama,
        base_url: "http://localhost:11434",
        timeout: 30_000

  ## Usage

  Start the application:

      mix deps.get
      iex -S mix

  Make API requests:

      curl -X POST http://localhost:4020/v1/llm/gemma \\
           -H "Content-Type: application/json" \\
           -d '{"prompt": "Explain quantum computing"}'

  Check system status:

      curl http://localhost:4020/v1/status

  ## API Endpoints

  - `POST /v1/llm/:model` - Submit prompt to specified model
  - `GET /v1/status` - Health check and resource usage

  See `Hermes.Router` for detailed endpoint documentation.
  """
end
