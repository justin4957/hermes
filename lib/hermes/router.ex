defmodule Hermes.Router do
  @moduledoc """
  HTTP router defining API endpoints for LLM interaction.

  This module uses Plug.Router to define RESTful HTTP endpoints for submitting
  prompts to LLM models and checking system health. All responses are JSON-encoded.

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

  plug :match
  plug Plug.Parsers, parsers: [:json], json_decoder: Jason
  plug :dispatch

  # POST /v1/llm/:model
  # Handles POST requests to generate text from an LLM model.
  # Extracts the model name from the URL path and the prompt from the request body,
  # then dispatches the generation request through `Hermes.Dispatcher`.
  # Returns JSON response with either the generated result or an error message.
  post "/v1/llm/:model" do
    case conn.body_params do
      %{"prompt" => prompt} when is_binary(prompt) ->
        case Hermes.Dispatcher.dispatch(model, prompt) do
          {:ok, response} ->
            send_resp(conn, 200, Jason.encode!(%{result: response}))
          {:error, reason} ->
            send_resp(conn, 500, Jason.encode!(%{error: inspect(reason)}))
        end
      _other ->
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
    send_resp(conn, 404, Jason.encode!(%{error: "Not found"}))
  end
end