# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is **Hermes** - an Elixir-based sidecar service designed to interface with Ollama for serving and scaling local LLM requests. The project is currently in planning phase with detailed development documentation but no implemented code yet.

## Architecture

### Core Design Principles
- **Minimalism**: Plug-based API, avoiding heavy web frameworks unless needed
- **Concurrency**: DynamicSupervisor + TaskSupervisor for handling multiple requests
- **Scalability**: Model-aware task limits with async processing
- **Efficiency**: On-demand model loading with resource monitoring
- **Interoperability**: Model-agnostic Ollama API integration

### Planned System Architecture
```
[ HTTP API ]
     ↓
[ Router (Plug) ]
     ↓
[ LLMRouter Dispatcher ]
     ↓
[ DynamicSupervisor → Task Supervisor ]
     ↓
[ Ollama HTTP Call → Response Stream ]
```

### Key Components (Planned)
- **LlmSidecar.Router**: Plug-based HTTP API for `/v1/llm/:model` and `/v1/status` endpoints
- **LlmSidecar.Ollama**: Client wrapper for Ollama REST API integration
- **LlmSidecar.Dispatcher**: Request routing and async task management
- **LlmSidecar.Supervisor**: Dynamic and Task supervisors for concurrency control

## Development Commands

This project is in planning phase. When implemented, it will be an Elixir project using:

### Standard Elixir Commands
```bash
# Create project (when ready to implement)
mix new llm_sidecar --sup

# Install dependencies
mix deps.get

# Start development server
iex -S mix

# Run tests
mix test

# Check code formatting
mix format --check-formatted

# Static analysis (if configured)
mix credo
mix dialyzer
```

### Planned Tech Stack Dependencies
- `plug_cowboy`: HTTP server
- `finch`: HTTP client for Ollama API calls  
- `jason`: JSON encoding/decoding
- `telemetry`: Metrics and monitoring (optional)

## Multi-Model Configuration

The system will support per-model configuration:
```elixir
config :llm_sidecar, :models,
  gemma: %{max_concurrency: 2, memory_cost: :medium},
  mistral: %{max_concurrency: 1, memory_cost: :high}
```

## API Endpoints (Planned)

| Endpoint | Method | Description |
|----------|---------|-------------|
| `/v1/llm/:model` | POST | Submit prompt to specified model |
| `/v1/status` | GET | Health check and resource usage |
| `/v1/llm/:model/pull` | POST | Pull and start model dynamically |

## Development Phases

1. **Foundation**: Project setup with Plug + Cowboy
2. **Ollama Interface**: HTTP client wrapper with timeout/retry logic  
3. **Concurrency**: DynamicSupervisor and request queueing
4. **Multi-Model**: Model switching and configuration management
5. **Autoscaling**: Resource awareness and throttling
6. **Monitoring**: Metrics and telemetry integration
7. **API**: REST endpoints and error handling
8. **Enhancements**: Streaming support and caching

## File Structure (Planned)
```
lib/
├── llm_sidecar.ex             # Entry module
├── llm_sidecar/application.ex # Supervision tree
├── llm_sidecar/router.ex      # HTTP API endpoints
├── llm_sidecar/ollama.ex      # Ollama client wrapper
├── llm_sidecar/supervisor.ex  # Dynamic + Task supervisors
└── llm_sidecar/dispatcher.ex  # Request routing logic
```

## Deployment Considerations

Designed as a **sidecar service** that can be deployed alongside main applications:
- Docker containers (lightweight, expose port, share Ollama connection)
- Systemd service for VPS/local deployments
- Cloud platforms (Fly.io, Nomad, bare metal) with minimal overhead