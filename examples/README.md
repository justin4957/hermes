# Hermes API Client Examples

This directory contains example client implementations for interacting with the Hermes LLM API in various programming languages.

## Prerequisites

Before running any examples, ensure:

1. **Hermes is running**: Start the service with `iex -S mix` from the project root
2. **Ollama is running**: Ensure Ollama is running on `http://localhost:11434`
3. **Models are available**: Pull required models with `ollama pull gemma` or `ollama pull llama3`

## Available Examples

### Python Client (`python_client.py`)

A Python 3 client using the `requests` library.

**Installation:**
```bash
pip install requests
```

**Usage:**
```bash
python python_client.py
```

**Features:**
- Simple class-based API
- Error handling examples
- Status check
- Multiple model generation

**Example code:**
```python
from python_client import HermesClient

client = HermesClient("http://localhost:4020")
result = client.generate("gemma", "What is Elixir?")
print(result['result'])
```

### JavaScript/Node.js Client (`javascript_client.js`)

A Node.js client using the native `fetch` API (Node.js 18+).

**Requirements:**
- Node.js 18 or higher

**Usage:**
```bash
node javascript_client.js
```

**Features:**
- Async/await pattern
- Modern fetch API
- Promise-based error handling
- Multiple model examples

**Example code:**
```javascript
const { HermesClient } = require('./javascript_client');

const client = new HermesClient('http://localhost:4020');
const result = await client.generate('gemma', 'What is Elixir?');
console.log(result.result);
```

### curl Examples (`curl_examples.sh`)

A shell script demonstrating various API calls using `curl`.

**Requirements:**
- `curl` command-line tool
- `python3` (for JSON formatting)

**Usage:**
```bash
./curl_examples.sh
```

**Includes:**
- Status check
- Basic text generation
- Error handling examples
- Multiple models
- Timing information

## Quick Start

1. Start Hermes:
   ```bash
   cd ..
   iex -S mix
   ```

2. In another terminal, run any example:
   ```bash
   # Python
   cd examples
   python python_client.py

   # JavaScript
   node javascript_client.js

   # curl
   ./curl_examples.sh
   ```

## API Reference

### Endpoints

#### POST /v1/llm/:model

Generate text from a model.

**Request:**
```json
{
  "prompt": "Your text prompt"
}
```

**Response (200 OK):**
```json
{
  "result": "Generated text response"
}
```

**Errors:**
- `400 Bad Request`: Missing or invalid prompt
- `500 Internal Server Error`: Generation failed or timeout

#### GET /v1/status

Get system health status.

**Response (200 OK):**
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

## Error Handling

All examples include error handling for common scenarios:

- **Connection refused**: Hermes is not running
- **404 Model not found**: Model not available in Ollama
- **400 Bad request**: Invalid prompt or JSON
- **500 Server error**: Generation timeout or failure

## Customization

### Change Base URL

All clients accept a custom base URL:

```python
# Python
client = HermesClient("http://your-server:4020")
```

```javascript
// JavaScript
const client = new HermesClient('http://your-server:4020');
```

```bash
# Shell
BASE_URL="http://your-server:4020" ./curl_examples.sh
```

### Add Timeout

```python
# Python
response = requests.post(url, json=payload, timeout=120)  # 2 minutes
```

```javascript
// JavaScript - using AbortController
const controller = new AbortController();
setTimeout(() => controller.abort(), 120000);
const response = await fetch(url, { signal: controller.signal });
```

## More Information

- Full API documentation: Run `mix docs` and open `doc/index.html`
- OpenAPI specification: See `openapi.yaml` in project root
- README: See `README.md` in project root
