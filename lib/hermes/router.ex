defmodule Hermes.Router do
  @moduledoc """
  HTTP router defining API endpoints for LLM interaction.

  This module uses Plug.Router to define RESTful HTTP endpoints for submitting
  prompts to LLM models and checking system health. All responses are JSON-encoded.

  ## Request Tracking

  All requests are assigned a unique request ID via the `x-request-id` header.
  If a request ID is provided by the client, it will be preserved; otherwise,
  a new one is generated. The request ID is included in all log entries and
  propagated through the request lifecycle for tracing.

  ## Telemetry Events

  The router emits telemetry events for observability:

  * `[:hermes, :request, :start]` - Request started
  * `[:hermes, :request, :stop]` - Request completed with status
  * `[:hermes, :request, :exception]` - Request failed with exception

  ## Endpoints

  ### POST /v1/llm/:model

  Submit a text prompt to a specified LLM model for generation.

  **Path Parameters:**
  - `model` - Name of the Ollama model (e.g., "gemma", "llama3", "mistral")

  **Request Body:**
  ```json
  {
    "prompt": "Your text prompt here"
  }
  ```

  **Success Response (200 OK):**
  ```json
  {
    "result": "Generated response text from the model"
  }
  ```

  **Error Responses:**
  - `400 Bad Request` - Missing or invalid prompt field
  - `404 Not Found` - Model not available in Ollama
  - `408 Request Timeout` - Generation exceeded timeout
  - `500 Internal Server Error` - Unexpected internal error
  - `502 Bad Gateway` - Ollama service error
  - `503 Service Unavailable` - Cannot connect to Ollama

  **Example:**
  ```bash
  curl -X POST http://localhost:4020/v1/llm/gemma \\
       -H "Content-Type: application/json" \\
       -d '{"prompt": "What is Elixir?"}'
  ```

  ### GET /v1/status

  Health check endpoint returning system metrics, dependency status, and resource usage.
  Suitable for Kubernetes liveness and readiness probes.

  **Success Response (200 OK):**
  ```json
  {
    "status": "healthy",
    "checks": {
      "ollama": "ok"
    },
    "version": "0.1.0",
    "uptime_seconds": 3600,
    "memory": {
      "total": 12345678,
      "processes": 4567890,
      "system": 7890123
    },
    "schedulers": 8,
    "models": ["gemma", "llama3", "mistral"]
  }
  ```

  **Unhealthy Response (503 Service Unavailable):**
  ```json
  {
    "status": "unhealthy",
    "checks": {
      "ollama": "error: connection_refused"
    },
    ...
  }
  ```

  **Example:**
  ```bash
  curl http://localhost:4020/v1/status
  ```

  ## Error Handling

  All errors return JSON responses with an `error` field:

  ```json
  {
    "error": "Description of what went wrong"
  }
  ```

  ## Content Type

  All endpoints expect and return `application/json`.
  """

  use Plug.Router

  require Logger

  alias Hermes.Error
  alias Hermes.Health
  alias Hermes.Telemetry

  # Add request ID for tracing
  plug(Plug.RequestId)
  # Telemetry for request timing
  plug(Plug.Telemetry, event_prefix: [:hermes, :request])
  plug(:match)
  plug(Plug.Parsers, parsers: [:json], json_decoder: Jason)
  plug(:set_logger_metadata)
  plug(:dispatch)

  # POST /v1/llm/:model
  # Handles POST requests to generate text from an LLM model.
  # Extracts the model name from the URL path and the prompt from the request body,
  # then dispatches the generation request through `Hermes.Dispatcher`.
  # Returns JSON response with either the generated result or an error message.
  post "/v1/llm/:model" do
    request_id = Telemetry.get_request_id(conn)

    case conn.body_params do
      %{"prompt" => prompt} when is_binary(prompt) ->
        prompt_length = String.length(prompt)

        Logger.info("LLM request started",
          request_id: request_id,
          model: model,
          prompt_length: prompt_length
        )

        case Hermes.Dispatcher.dispatch(model, prompt, request_id: request_id) do
          {:ok, response} ->
            Logger.info("LLM request completed",
              request_id: request_id,
              model: model,
              response_length: String.length(response)
            )

            send_resp(conn, 200, Jason.encode!(%{result: response}))

          {:error, error} ->
            status_code = Error.http_status(error)
            error_type = Error.type(error)

            Logger.error("LLM request failed",
              request_id: request_id,
              model: model,
              error_type: error_type,
              status_code: status_code,
              error: Error.message(error)
            )

            send_resp(conn, status_code, Jason.encode!(Error.to_map(error)))
        end

      _other ->
        validation_error =
          Error.ValidationError.new(
            "Missing 'prompt' field or invalid JSON",
            field: "prompt"
          )

        Logger.warning("Invalid LLM request: missing prompt",
          request_id: request_id,
          model: model
        )

        send_resp(conn, 400, Jason.encode!(Error.to_map(validation_error)))
    end
  end

  # GET /v1/status
  # Handles GET requests for system health and status information.
  # Performs health checks on dependencies and returns comprehensive status.
  # Returns 200 if healthy, 503 if any dependency is unhealthy.
  get "/v1/status" do
    health = Health.check()
    status_code = Health.http_status(health)
    response = Health.to_json(health)

    send_resp(conn, status_code, Jason.encode!(response))
  end

  # Catch-all handler for undefined routes.
  # Returns 404 Not Found for any request that doesn't match defined endpoints.
  match _ do
    request_id = Telemetry.get_request_id(conn)

    Logger.debug("Route not found",
      request_id: request_id,
      method: conn.method,
      path: conn.request_path
    )

    send_resp(conn, 404, Jason.encode!(%{error: "Not found"}))
  end

  # Private plugs

  defp set_logger_metadata(conn, _opts) do
    request_id = Telemetry.get_request_id(conn)

    Logger.metadata(
      request_id: request_id,
      method: conn.method,
      path: conn.request_path
    )

    conn
  end
end
