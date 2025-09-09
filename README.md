# Hermes - LLM Sidecar Service

A minimal, efficient Elixir-based sidecar service that interfaces with Ollama to serve and scale local LLM requests.

## Features

- **Concurrent Processing**: Handle multiple LLM requests simultaneously using Elixir's actor model
- **Multiple Model Support**: Switch between different models (Gemma, Llama3, Mistral, etc.)
- **Resource Management**: Built-in timeout handling and resource monitoring
- **HTTP API**: Simple REST endpoints for LLM interaction
- **Fault Tolerance**: Supervised processes with graceful error handling

## Quick Start

1. **Install Dependencies**:
   ```bash
   mix deps.get
   ```

2. **Start Ollama** (ensure it's running on localhost:11434):
   ```bash
   # Install and start Ollama separately
   ollama serve
   ```

3. **Run the Application**:
   ```bash
   iex -S mix
   ```

4. **Test the API**:
   ```bash
   # Submit a prompt to a model
   curl -X POST http://localhost:4020/v1/llm/gemma \
        -H "Content-Type: application/json" \
        -d '{"prompt": "Explain quantum computing"}'

   # Check system status
   curl http://localhost:4020/v1/status
   ```

## API Endpoints

| Endpoint | Method | Description |
|----------|---------|-------------|
| `/v1/llm/:model` | POST | Submit prompt to specified model |
| `/v1/status` | GET | Health check and resource usage |

### Example Request/Response

**Request**:
```bash
curl -X POST http://localhost:4020/v1/llm/gemma \
     -H "Content-Type: application/json" \
     -d '{"prompt": "What is Elixir?"}'
```

**Response**:
```json
{
  "result": "Elixir is a dynamic, functional programming language designed for building maintainable and scalable applications..."
}
```

## Configuration

Configure models and resource limits in `config/config.exs`:

```elixir
config :llm_sidecar, :models,
  gemma: %{max_concurrency: 2, memory_cost: :medium, timeout: 30_000},
  llama3: %{max_concurrency: 1, memory_cost: :high, timeout: 45_000},
  mistral: %{max_concurrency: 2, memory_cost: :medium, timeout: 30_000}
```

## Architecture

```
[ HTTP API ]
     ↓
[ Router (Plug) ]
     ↓
[ Dispatcher ]
     ↓
[ Task Supervisor ]
     ↓
[ Ollama HTTP Client ]
```

## Development

- **Start Development Server**: `iex -S mix`
- **Run Tests**: `mix test`
- **Format Code**: `mix format`

## Production Deployment

Set environment variables:
- `PORT`: HTTP server port (default: 4000)
- `OLLAMA_URL`: Ollama server URL (default: http://localhost:11434)

```bash
# Build release
MIX_ENV=prod mix release

# Run in production
PORT=4020 OLLAMA_URL=http://ollama:11434 _build/prod/rel/hermes/bin/hermes start
```