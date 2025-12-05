defmodule Hermes.Ollama do
  @moduledoc """
  HTTP client for interacting with the Ollama REST API.

  This module provides functions for sending generation requests to a locally
  running Ollama instance. It handles request formatting, response parsing,
  and error cases.

  ## Configuration

  The Ollama base URL and timeout can be configured in `config/config.exs`:

      config :hermes, :ollama,
        base_url: "http://localhost:11434",
        timeout: 30_000

  ## Examples

      # Generate text with default timeout
      {:ok, response} = Hermes.Ollama.generate("gemma", "What is Elixir?")

      # Generate with custom timeout
      {:ok, response} = Hermes.Ollama.generate("llama3", "Explain AI", timeout: 60_000)

      # Handle errors
      case Hermes.Ollama.generate("invalid-model", "test") do
        {:ok, response} -> IO.puts(response)
        {:error, reason} -> IO.puts("Error: \#{reason}")
      end
  """

  @behaviour Hermes.OllamaBehaviour

  alias Hermes.Config

  @doc """
  Generates text completion from an Ollama model.

  Sends a prompt to the specified Ollama model and returns the generated response.
  The request is made in non-streaming mode, returning the complete response once
  generation is finished.

  ## Parameters

    * `model` - String name of the Ollama model to use (e.g., "gemma", "llama3")
    * `prompt` - String containing the text prompt to send to the model
    * `opts` - Keyword list of options:
      * `:timeout` - Request timeout in milliseconds (default: 30,000)

  ## Returns

    * `{:ok, response}` - On success, returns the generated text response
    * `{:error, reason}` - On failure, returns error description

  ## Examples

      iex> Hermes.Ollama.generate("gemma", "Hello")
      {:ok, "Hello! How can I assist you today?"}

      iex> Hermes.Ollama.generate("llama3", "2+2=?", timeout: 10_000)
      {:ok, "2 + 2 = 4"}

      iex> Hermes.Ollama.generate("nonexistent", "test")
      {:error, "HTTP 404: model not found"}
  """
  @spec generate(String.t(), String.t(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def generate(model, prompt, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, Config.ollama_timeout())
    url = build_url(opts)

    body =
      Jason.encode!(%{
        model: model,
        prompt: prompt,
        stream: false
      })

    finch_name = Keyword.get(opts, :finch_name, Hermes.Finch)

    Finch.build(:post, url, [{"content-type", "application/json"}], body)
    |> Finch.request(finch_name, receive_timeout: timeout)
    |> handle_response()
  end

  defp build_url(opts) do
    base_url = Keyword.get(opts, :base_url) || Config.ollama_url()
    "#{base_url}/api/generate"
  end

  defp handle_response({:ok, %{status: 200, body: resp_body}}) do
    case Jason.decode(resp_body) do
      {:ok, %{"response" => response}} ->
        {:ok, response}

      {:ok, parsed} ->
        {:error, "Unexpected response format: #{inspect(parsed)}"}

      {:error, decode_error} ->
        {:error, "JSON decode error: #{inspect(decode_error)}"}
    end
  end

  defp handle_response({:ok, %{status: status, body: body}}) do
    {:error, "HTTP #{status}: #{body}"}
  end

  defp handle_response({:error, reason}) do
    {:error, "Request failed: #{inspect(reason)}"}
  end
end
