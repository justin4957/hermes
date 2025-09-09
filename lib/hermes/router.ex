defmodule Hermes.Router do
  use Plug.Router

  plug :match
  plug Plug.Parsers, parsers: [:json], json_decoder: Jason
  plug :dispatch

  post "/v1/llm/:model" do
    case conn.body_params do
      %{"prompt" => prompt} when is_binary(prompt) ->
        case Hermes.Dispatcher.dispatch(model, prompt) do
          {:ok, response} ->
            send_resp(conn, 200, Jason.encode!(%{result: response}))
          {:error, reason} ->
            send_resp(conn, 500, Jason.encode!(%{error: inspect(reason)}))
        end
      _other ->
        send_resp(conn, 400, Jason.encode!(%{error: "Missing 'prompt' field or invalid JSON"}))
    end
  end

  get "/v1/status" do
    memory_info = :erlang.memory()
    system_info = %{
      status: "ok",
      memory: %{
        total: memory_info[:total],
        processes: memory_info[:processes],
        system: memory_info[:system]
      },
      schedulers: System.schedulers_online()
    }
    
    send_resp(conn, 200, Jason.encode!(system_info))
  end

  match _ do
    send_resp(conn, 404, Jason.encode!(%{error: "Not found"}))
  end
end