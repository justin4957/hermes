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
  - `500 Internal Server Error` - Generation failed or timeout

  **Example:**
  ```bash
  curl -X POST http://localhost:4020/v1/llm/gemma \\
       -H "Content-Type: application/json" \\
       -d '{"prompt": "What is Elixir?"}'
  ```

  ### GET /v1/status

  Health check endpoint returning system metrics and resource usage.

  **Success Response (200 OK):**
  ```json
  {
    "status": "ok",
    "memory": {
      "total": 12345678,
      "processes": 4567890,
      "system": 7890123
    },
    "schedulers": 8
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

          {:error, reason} ->
            Logger.error("LLM request failed",
              request_id: request_id,
              model: model,
              error: inspect(reason)
            )

            send_resp(conn, 500, Jason.encode!(%{error: inspect(reason)}))
        end

      _other ->
        Logger.warning("Invalid LLM request: missing prompt",
          request_id: request_id,
          model: model
        )

        send_resp(conn, 400, Jason.encode!(%{error: "Missing 'prompt' field or invalid JSON"}))
    end
  end

  # GET /v1/status
  # Handles GET requests for system health and status information.
  # Returns current BEAM VM memory statistics and scheduler information,
  # useful for monitoring and health checks.
  get "/v1/status" do
    memory_info = :erlang.memory()

    system_info = %{
      status: "ok",
      memory: %{
        total: memory_info[:total],
        processes: memory_info[:processes],
        system: memory_info[:system]
      },
      schedulers: System.schedulers_online()
    }

    send_resp(conn, 200, Jason.encode!(system_info))
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
