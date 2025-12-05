# Hermes - LLM Sidecar Service

[![CI](https://github.com/justin4957/hermes/actions/workflows/ci.yml/badge.svg)](https://github.com/justin4957/hermes/actions/workflows/ci.yml)
[![Coverage Status](https://coveralls.io/repos/github/justin4957/hermes/badge.svg?branch=main)](https://coveralls.io/github/justin4957/hermes?branch=main)

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

| Endpoint | Method | Description | Status Codes |
|----------|---------|-------------|--------------|
| `/v1/llm/:model` | POST | Submit prompt to specified model | 200, 400, 500 |
| `/v1/status` | GET | Health check and resource usage | 200 |

### POST /v1/llm/:model

Generate text completion from a specified LLM model.

**Path Parameters:**
- `model` - Name of Ollama model (e.g., `gemma`, `llama3`, `mistral`)

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
- `500 Internal Server Error` - Generation failed, timeout, or Ollama error

**Example Request:**
```bash
curl -X POST http://localhost:4020/v1/llm/gemma \
     -H "Content-Type: application/json" \
     -d '{"prompt": "What is Elixir?"}'
```

**Example Response:**
```json
{
  "result": "Elixir is a dynamic, functional programming language designed for building maintainable and scalable applications..."
}
```

### GET /v1/status

Retrieve system health and resource metrics.

**Success Response (200 OK):**
```json
{
  "status": "ok",
  "memory": {
    "total": 45678912,
    "processes": 12345678,
    "system": 23456789
  },
  "schedulers": 8
}
```

**Example Request:**
```bash
curl http://localhost:4020/v1/status
```

## Configuration

Hermes can be configured via environment variables or application config files. Environment variables take precedence over config file settings.

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `PORT` | HTTP server port | `4020` |
| `OLLAMA_URL` | Ollama server base URL | `http://localhost:11434` |
| `OLLAMA_TIMEOUT` | Default request timeout (milliseconds) | `30000` |

**Example:**
```bash
PORT=8080 OLLAMA_URL=http://ollama:11434 iex -S mix
```

### Application Config

Configure in `config/config.exs` or environment-specific files (`dev.exs`, `prod.exs`, `test.exs`):

#### HTTP Server

```elixir
config :hermes, :http,
  port: 4020
```

#### Ollama Connection

```elixir
config :hermes, :ollama,
  base_url: "http://localhost:11434",
  timeout: 30_000  # Default timeout in milliseconds
```

#### Model-Specific Configuration

Each model can have its own timeout, concurrency limits, and resource settings:

```elixir
config :hermes, :models,
  gemma: %{max_concurrency: 2, memory_cost: :medium, timeout: 30_000},
  llama3: %{max_concurrency: 1, memory_cost: :high, timeout: 45_000},
  mistral: %{max_concurrency: 2, memory_cost: :medium, timeout: 30_000},
  codellama: %{max_concurrency: 1, memory_cost: :high, timeout: 60_000}
```

**Model Config Options:**

| Option | Type | Description |
|--------|------|-------------|
| `timeout` | integer | Request timeout in milliseconds |
| `max_concurrency` | integer | Maximum concurrent requests for this model |
| `memory_cost` | atom | Memory usage category (`:low`, `:medium`, `:high`) |

### Configuration Priority

Values are resolved in the following order (highest to lowest priority):

1. Environment variables (`PORT`, `OLLAMA_URL`, `OLLAMA_TIMEOUT`)
2. Environment-specific config (`dev.exs`, `prod.exs`, `test.exs`)
3. Base config (`config.exs`)
4. Default values in code

### Timeout Resolution

When a request is made, the timeout is determined by:

1. Explicit timeout passed in the request (if any)
2. Model-specific timeout from config
3. Default Ollama timeout from config
4. Built-in default (30 seconds)

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

## Error Handling

All errors return JSON with an `error` field describing the issue:

```json
{
  "error": "Description of what went wrong"
}
```

**Common Errors:**

| Error Message | Cause | Solution |
|--------------|-------|----------|
| `Missing 'prompt' field or invalid JSON` | Request body missing `prompt` or invalid JSON | Ensure JSON is valid and includes `prompt` field |
| `Request timeout after Xms` | Generation exceeded timeout limit | Increase timeout or simplify prompt |
| `Request failed: connection refused` | Cannot connect to Ollama | Ensure Ollama is running on configured URL |
| `HTTP 404: model not found` | Requested model not available in Ollama | Pull the model: `ollama pull <model>` |

## Development

- **Start Development Server**: `iex -S mix`
- **Run Tests**: `mix test`
- **Format Code**: `mix format`
- **Generate Documentation**: `mix docs`

## Documentation

Comprehensive API documentation is available:

- **ExDoc**: Generate HTML documentation with `mix docs`, then open `doc/index.html`
- **OpenAPI Spec**: See `openapi.yaml` for full API specification
- **Code Examples**: See `examples/` directory for client implementations

## Production Deployment

### Environment Variables

Set these environment variables to configure the production deployment:

| Variable | Description | Default |
|----------|-------------|---------|
| `PORT` | HTTP server port | `4020` |
| `OLLAMA_URL` | Ollama server URL | `http://localhost:11434` |
| `OLLAMA_TIMEOUT` | Request timeout (ms) | `30000` |

### Building and Running

```bash
# Build release
MIX_ENV=prod mix release

# Run in production with custom configuration
PORT=8080 OLLAMA_URL=http://ollama:11434 _build/prod/rel/hermes/bin/hermes start
```

### Docker Example

```dockerfile
FROM elixir:1.16-alpine AS build
WORKDIR /app
COPY . .
RUN mix deps.get --only prod
RUN MIX_ENV=prod mix release

FROM alpine:3.19
WORKDIR /app
COPY --from=build /app/_build/prod/rel/hermes ./
ENV PORT=4020
ENV OLLAMA_URL=http://ollama:11434
CMD ["bin/hermes", "start"]
```

## Troubleshooting

### Ollama Connection Issues

**Problem**: `Request failed: connection refused`

**Solutions**:
1. Verify Ollama is running: `curl http://localhost:11434/api/tags`
2. Check configured URL in `config/config.exs`
3. Ensure Ollama is accessible from Hermes host

### Model Not Found

**Problem**: `HTTP 404: model not found`

**Solutions**:
1. List available models: `ollama list`
2. Pull the model: `ollama pull gemma`
3. Verify model name matches Ollama's naming

### Timeout Errors

**Problem**: `Request timeout after 30000ms`

**Solutions**:
1. Increase timeout in config:
   ```elixir
   config :hermes, :models,
     gemma: %{timeout: 60_000}  # 60 seconds
   ```
2. Simplify or shorten the prompt
3. Use a faster/smaller model

### High Memory Usage

**Problem**: Memory usage growing over time

**Solutions**:
1. Check `/v1/status` endpoint for memory metrics
2. Reduce concurrent request load
3. Lower `max_concurrency` in model config
4. Restart the service periodically

### Port Already in Use

**Problem**: `eaddrinuse` error on startup

**Solutions**:
1. Change port in `config/config.exs` or set `PORT` env var
2. Kill process using port: `lsof -ti:4020 | xargs kill`
3. Check for other Hermes instances running

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes with tests
4. Run `mix format` and `mix docs`
5. Submit a pull request

## License

MIT License - see LICENSE file for details