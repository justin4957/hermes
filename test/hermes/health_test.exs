defmodule Hermes.HealthTest do
  use ExUnit.Case, async: true

  alias Hermes.Health

  describe "version/0" do
    test "returns application version" do
      version = Health.version()
      assert is_binary(version)
      # Version should match pattern like "0.1.0"
      assert version =~ ~r/^\d+\.\d+\.\d+$/ or version == "unknown"
    end
  end

  describe "uptime_seconds/0" do
    test "returns non-negative integer" do
      uptime = Health.uptime_seconds()
      assert is_integer(uptime)
      assert uptime >= 0
    end

    test "increases over time" do
      uptime1 = Health.uptime_seconds()
      Process.sleep(10)
      uptime2 = Health.uptime_seconds()
      # Uptime should stay the same or increase
      assert uptime2 >= uptime1
    end
  end

  describe "record_start_time/0" do
    test "returns :ok" do
      assert :ok = Health.record_start_time()
    end
  end

  describe "check_ollama/1" do
    setup do
      bypass = Bypass.open()
      {:ok, bypass: bypass}
    end

    test "returns :ok when Ollama is healthy", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/api/tags", fn conn ->
        Plug.Conn.resp(conn, 200, Jason.encode!(%{models: []}))
      end)

      result = Health.check_ollama(base_url: "http://localhost:#{bypass.port}")
      assert result == :ok
    end

    test "returns error on non-2xx status", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/api/tags", fn conn ->
        Plug.Conn.resp(conn, 500, "Internal Server Error")
      end)

      result = Health.check_ollama(base_url: "http://localhost:#{bypass.port}")
      assert {:error, _reason} = result
    end

    test "returns error when Ollama is unreachable" do
      # Use a port that's definitely not in use
      result = Health.check_ollama(base_url: "http://localhost:59999", timeout: 100)
      assert {:error, _reason} = result
    end
  end

  describe "check/1" do
    setup do
      bypass = Bypass.open()
      {:ok, bypass: bypass}
    end

    test "returns healthy status when Ollama is available", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/api/tags", fn conn ->
        Plug.Conn.resp(conn, 200, Jason.encode!(%{models: []}))
      end)

      result = Health.check(base_url: "http://localhost:#{bypass.port}")

      assert result.status == :healthy
      assert result.checks.ollama == :ok
      assert is_binary(result.version)
      assert is_integer(result.uptime_seconds)
      assert is_map(result.memory)
      assert is_integer(result.schedulers)
      assert is_list(result.models)
    end

    test "returns unhealthy status when Ollama is unavailable", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/api/tags", fn conn ->
        Plug.Conn.resp(conn, 500, "Error")
      end)

      result = Health.check(base_url: "http://localhost:#{bypass.port}")

      assert result.status == :unhealthy
      assert {:error, _} = result.checks.ollama
    end

    test "skips Ollama check when skip_ollama is true" do
      result = Health.check(skip_ollama: true)

      assert result.status == :healthy
      assert result.checks.ollama == :skipped
    end

    test "includes memory statistics" do
      result = Health.check(skip_ollama: true)

      assert is_integer(result.memory.total)
      assert is_integer(result.memory.processes)
      assert is_integer(result.memory.system)
      assert result.memory.total > 0
    end

    test "includes scheduler count" do
      result = Health.check(skip_ollama: true)

      assert result.schedulers > 0
      assert result.schedulers == System.schedulers_online()
    end

    test "includes configured models" do
      result = Health.check(skip_ollama: true)

      assert is_list(result.models)
      assert Enum.all?(result.models, &is_binary/1)
    end
  end

  describe "http_status/1" do
    test "returns 200 for healthy status" do
      assert Health.http_status(%{status: :healthy}) == 200
    end

    test "returns 503 for unhealthy status" do
      assert Health.http_status(%{status: :unhealthy}) == 503
    end
  end

  describe "to_json/1" do
    test "converts health map to JSON-serializable format" do
      health = %{
        status: :healthy,
        checks: %{ollama: :ok},
        version: "0.1.0",
        uptime_seconds: 3600,
        memory: %{total: 100, processes: 50, system: 50},
        schedulers: 8,
        models: ["gemma", "llama3"]
      }

      json = Health.to_json(health)

      assert json.status == "healthy"
      assert json.checks.ollama == "ok"
      assert json.version == "0.1.0"
      assert json.uptime_seconds == 3600
      assert json.schedulers == 8
      assert json.models == ["gemma", "llama3"]
    end

    test "converts error checks to strings" do
      health = %{
        status: :unhealthy,
        checks: %{ollama: {:error, :connection_refused}},
        version: "0.1.0",
        uptime_seconds: 0,
        memory: %{total: 100, processes: 50, system: 50},
        schedulers: 8,
        models: []
      }

      json = Health.to_json(health)

      assert json.status == "unhealthy"
      assert json.checks.ollama == "error: connection_refused"
    end

    test "converts skipped checks to strings" do
      health = %{
        status: :healthy,
        checks: %{ollama: :skipped},
        version: "0.1.0",
        uptime_seconds: 0,
        memory: %{total: 100, processes: 50, system: 50},
        schedulers: 8,
        models: []
      }

      json = Health.to_json(health)

      assert json.checks.ollama == "skipped"
    end
  end
end
