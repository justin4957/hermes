defmodule Hermes.OllamaBehaviour do
  @moduledoc """
  Behaviour definition for the Ollama HTTP client.

  This behaviour allows for dependency injection and mocking in tests.
  """

  @doc """
  Generates text completion from an Ollama model (non-streaming).

  Returns the complete response once generation is finished.
  """
  @callback generate(String.t(), String.t(), keyword()) ::
              {:ok, String.t()} | {:error, Hermes.Error.error()}

  @doc """
  Generates text completion from an Ollama model with streaming.

  Invokes the callback function with each streamed chunk as it arrives.
  The callback receives:
  - `{:chunk, text}` - A partial response chunk
  - `{:done, nil}` - Streaming completed successfully
  - `{:error, error}` - An error occurred during streaming
  """
  @callback generate_stream(String.t(), String.t(), (term() -> any()), keyword()) ::
              :ok | {:error, Hermes.Error.error()}
end
