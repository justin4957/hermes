Got it 👍 — you already have a strong phased plan. Here’s a **code + directory scaffold** you can use right away as a starting point for your Elixir sidecar project. I’ll keep it minimal but with the right hooks for Ollama, concurrency, and future scaling.

---

# 📂 Scaffolded Elixir Sidecar

```
llm_sidecar/
├── lib/
│   ├── llm_sidecar.ex             # Entry module
│   ├── llm_sidecar/application.ex # Supervision tree
│   ├── llm_sidecar/router.ex      # Plug router (HTTP API)
│   ├── llm_sidecar/ollama.ex      # Ollama client wrapper
│   ├── llm_sidecar/supervisor.ex  # Dynamic + Task supervisors
│   └── llm_sidecar/dispatcher.ex  # Routes requests to workers
├── config/
│   ├── config.exs
│   ├── dev.exs
│   └── prod.exs
├── mix.exs
└── README.md
```

---

## 🔹 `mix.exs`

```elixir
defmodule LlmSidecar.MixProject do
  use Mix.Project

  def project do
    [
      app: :llm_sidecar,
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      mod: {LlmSidecar.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp deps do
    [
      {:plug_cowboy, "~> 2.7"},
      {:finch, "~> 0.16"},
      {:jason, "~> 1.4"}
    ]
  end
end
```

---

## 🔹 `lib/llm_sidecar/application.ex`

```elixir
defmodule LlmSidecar.Application do
  use Application

  def start(_type, _args) do
    children = [
      {Finch, name: LlmSidecar.Finch},
      LlmSidecar.Supervisor,
      {Plug.Cowboy, scheme: :http, plug: LlmSidecar.Router, options: [port: 4000]}
    ]

    opts = [strategy: :one_for_one, name: LlmSidecar.AppSupervisor]
    Supervisor.start_link(children, opts)
  end
end
```

---

## 🔹 `lib/llm_sidecar/router.ex`

```elixir
defmodule LlmSidecar.Router do
  use Plug.Router

  plug :match
  plug Plug.Parsers, parsers: [:json], json_decoder: Jason
  plug :dispatch

  post "/v1/llm/:model" do
    {:ok, body, _conn} = Plug.Conn.read_body(conn)
    %{"prompt" => prompt} = Jason.decode!(body)

    case LlmSidecar.Dispatcher.dispatch(model, prompt) do
      {:ok, response} ->
        send_resp(conn, 200, Jason.encode!(%{result: response}))
      {:error, reason} ->
        send_resp(conn, 500, Jason.encode!(%{error: inspect(reason)}))
    end
  end

  get "/v1/status" do
    send_resp(conn, 200, Jason.encode!(%{status: "ok"}))
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end
end
```

---

## 🔹 `lib/llm_sidecar/ollama.ex`

```elixir
defmodule LlmSidecar.Ollama do
  @moduledoc "Client for Ollama REST API"
  @url "http://localhost:11434/api/generate"

  def generate(model, prompt) do
    body = Jason.encode!(%{model: model, prompt: prompt, stream: false})

    Finch.build(:post, @url, [{"content-type", "application/json"}], body)
    |> Finch.request(LlmSidecar.Finch)
    |> case do
      {:ok, %{status: 200, body: resp_body}} ->
        {:ok, Jason.decode!(resp_body)["response"]}
      other ->
        {:error, other}
    end
  end
end
```

---

## 🔹 `lib/llm_sidecar/dispatcher.ex`

```elixir
defmodule LlmSidecar.Dispatcher do
  def dispatch(model, prompt) do
    Task.Supervisor.async_nolink(LlmSidecar.TaskSupervisor, fn ->
      LlmSidecar.Ollama.generate(model, prompt)
    end)
    |> Task.await(30_000)
  end
end
```

---

## 🔹 `lib/llm_sidecar/supervisor.ex`

```elixir
defmodule LlmSidecar.Supervisor do
  use Supervisor

  def start_link(_init_arg) do
    Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    children = [
      {Task.Supervisor, name: LlmSidecar.TaskSupervisor, strategy: :one_for_one}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
```

---

## ✅ Next Steps

* **Phase 3**: Add rate-limiting / backpressure in `Dispatcher`.
* **Phase 4**: Extend `config.exs` to define per-model concurrency rules.
* **Phase 5+**: Add telemetry & metrics exposure (`/metrics` endpoint).

---

Would you like me to **generate this as a zip-able template repo** (so you can `mix deps.get` and run `iex -S mix` immediately), or do you prefer I keep everything inline here so you can copy-paste into your own project?

