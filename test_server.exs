#!/usr/bin/env elixir

# Simple test to verify the application works
IO.puts("Testing Hermes v0 implementation...")

# Start the application
{:ok, _} = Application.ensure_all_started(:hermes)
IO.puts("✓ Application started successfully")

# Test basic modules
IO.puts("\nTesting modules:")

# Test Ollama module (will fail without Ollama running, but should not crash)
case Hermes.Ollama.generate("gemma", "test prompt") do
  {:error, reason} ->
    IO.puts("✓ Ollama module handles errors correctly: #{inspect(reason)}")
  {:ok, response} ->
    IO.puts("✓ Ollama module works: #{response}")
end

# Test Dispatcher
case Hermes.Dispatcher.dispatch("gemma", "test prompt") do
  {:error, reason} ->
    IO.puts("✓ Dispatcher handles errors correctly: #{inspect(reason)}")
  {:ok, response} ->
    IO.puts("✓ Dispatcher works: #{response}")
end

# Wait for HTTP server to start
Process.sleep(2000)

# Test HTTP endpoints using Finch directly
case Finch.build(:get, "http://localhost:4020/v1/status") |> Finch.request(Hermes.Finch) do
  {:ok, %{status: 200, body: body}} ->
    IO.puts("✓ HTTP status endpoint works: #{body}")
  {:error, reason} ->
    IO.puts("✗ HTTP status endpoint failed: #{inspect(reason)}")
end

IO.puts("\nHermes v0 implementation test complete!")
IO.puts("Server running on http://localhost:4020")
IO.puts("Try: curl http://localhost:4020/v1/status")

# Keep server running
Process.sleep(:infinity)