#!/bin/bash
#
# Hermes API - curl Examples
#
# This file demonstrates various ways to interact with the Hermes API using curl.
# Make sure Hermes is running on http://localhost:4020 before executing these commands.

set -e  # Exit on error

BASE_URL="http://localhost:4020"

echo "========================================="
echo "Hermes API - curl Examples"
echo "========================================="
echo ""

# Check if Hermes is running
echo "1. Checking if Hermes is running..."
if curl -s -f "${BASE_URL}/v1/status" > /dev/null; then
    echo "✓ Hermes is running"
else
    echo "✗ Hermes is not running on ${BASE_URL}"
    echo "  Start it with: iex -S mix"
    exit 1
fi
echo ""

# Get system status
echo "2. Getting system status..."
curl -s "${BASE_URL}/v1/status" | python3 -m json.tool
echo ""
echo ""

# Generate text with Gemma model
echo "3. Generating text with Gemma model..."
curl -s -X POST "${BASE_URL}/v1/llm/gemma" \
     -H "Content-Type: application/json" \
     -d '{"prompt": "What is Elixir?"}' \
     | python3 -m json.tool
echo ""
echo ""

# Generate text with custom prompt
echo "4. Generating text with a more complex prompt..."
curl -s -X POST "${BASE_URL}/v1/llm/gemma" \
     -H "Content-Type: application/json" \
     -d '{
       "prompt": "Explain the actor model in concurrent programming in 2-3 sentences."
     }' \
     | python3 -m json.tool
echo ""
echo ""

# Example: Missing prompt field (400 error)
echo "5. Testing error handling - missing prompt field..."
curl -s -X POST "${BASE_URL}/v1/llm/gemma" \
     -H "Content-Type: application/json" \
     -d '{}' \
     | python3 -m json.tool
echo ""
echo ""

# Example: Invalid JSON (400 error)
echo "6. Testing error handling - invalid JSON..."
curl -s -X POST "${BASE_URL}/v1/llm/gemma" \
     -H "Content-Type: application/json" \
     -d 'not json' \
     | python3 -m json.tool
echo ""
echo ""

# Example: Undefined route (404 error)
echo "7. Testing error handling - undefined route..."
curl -s "${BASE_URL}/v1/undefined" \
     | python3 -m json.tool
echo ""
echo ""

# Example: Using different model
echo "8. Generating text with Llama3 model..."
curl -s -X POST "${BASE_URL}/v1/llm/llama3" \
     -H "Content-Type: application/json" \
     -d '{"prompt": "What is 2+2?"}' \
     | python3 -m json.tool
echo ""
echo ""

# Example: Verbose output with timing
echo "9. Request with timing information..."
curl -w "\nTime: %{time_total}s\n" \
     -X POST "${BASE_URL}/v1/llm/gemma" \
     -H "Content-Type: application/json" \
     -d '{"prompt": "Hello!"}' \
     | python3 -m json.tool
echo ""

echo "========================================="
echo "Examples completed!"
echo "========================================="
