defmodule Hermes.OllamaBehaviour do
  @moduledoc """
  Behaviour definition for the Ollama HTTP client.

  This behaviour allows for dependency injection and mocking in tests.
  """

  @callback generate(String.t(), String.t(), keyword()) ::
              {:ok, String.t()} | {:error, String.t()}
end
