defmodule Hermes.Ollama do
  @moduledoc "Client for Ollama REST API"
  
  @url "http://localhost:11434/api/generate"

  def generate(model, prompt, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    
    body = Jason.encode!(%{
      model: model, 
      prompt: prompt, 
      stream: false
    })

    Finch.build(:post, @url, [{"content-type", "application/json"}], body)
    |> Finch.request(Hermes.Finch, receive_timeout: timeout)
    |> handle_response()
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