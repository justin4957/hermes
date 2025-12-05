defmodule Hermes.TelemetryTest do
  use ExUnit.Case, async: true

  alias Hermes.Telemetry

  describe "generate_request_id/0" do
    test "generates a unique request ID" do
      request_id = Telemetry.generate_request_id()

      assert is_binary(request_id)
      assert String.length(request_id) > 0
    end

    test "generates different IDs on each call" do
      id1 = Telemetry.generate_request_id()
      id2 = Telemetry.generate_request_id()

      assert id1 != id2
    end

    test "generates URL-safe base64 encoded string" do
      request_id = Telemetry.generate_request_id()

      # URL-safe base64 should not contain + or /
      refute String.contains?(request_id, "+")
      refute String.contains?(request_id, "/")
    end
  end

  describe "span/3" do
    setup do
      test_pid = self()

      handler_id = "test-handler-#{System.unique_integer()}"

      :telemetry.attach_many(
        handler_id,
        [
          [:test, :span, :start],
          [:test, :span, :stop],
          [:test, :span, :exception]
        ],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn ->
        :telemetry.detach(handler_id)
      end)

      :ok
    end

    test "emits start and stop events on success" do
      result =
        Telemetry.span([:test, :span], %{test_key: "test_value"}, fn ->
          {:ok, "success"}
        end)

      assert result == {:ok, "success"}

      assert_receive {:telemetry_event, [:test, :span, :start], start_measurements,
                      start_metadata}

      assert is_integer(start_measurements.system_time)
      assert start_metadata.test_key == "test_value"

      assert_receive {:telemetry_event, [:test, :span, :stop], stop_measurements, stop_metadata}
      assert is_integer(stop_measurements.duration)
      assert stop_metadata.test_key == "test_value"
      assert stop_metadata.result == {:ok, "success"}
    end

    test "emits exception event on error and re-raises" do
      assert_raise RuntimeError, "test error", fn ->
        Telemetry.span([:test, :span], %{model: "gemma"}, fn ->
          raise "test error"
        end)
      end

      assert_receive {:telemetry_event, [:test, :span, :start], _start_measurements,
                      _start_metadata}

      assert_receive {:telemetry_event, [:test, :span, :exception], exception_measurements,
                      exception_metadata}

      assert is_integer(exception_measurements.duration)
      assert exception_metadata.model == "gemma"
      assert exception_metadata.kind == :error
      assert %RuntimeError{message: "test error"} = exception_metadata.reason
    end

    test "emits exception event on throw" do
      catch_throw do
        Telemetry.span([:test, :span], %{}, fn ->
          throw(:test_throw)
        end)
      end

      assert_receive {:telemetry_event, [:test, :span, :start], _start_measurements,
                      _start_metadata}

      assert_receive {:telemetry_event, [:test, :span, :exception], exception_measurements,
                      exception_metadata}

      assert is_integer(exception_measurements.duration)
      assert exception_metadata.kind == :throw
      assert exception_metadata.reason == :test_throw
    end

    test "emits exception event on exit" do
      catch_exit do
        Telemetry.span([:test, :span], %{}, fn ->
          exit(:test_exit)
        end)
      end

      assert_receive {:telemetry_event, [:test, :span, :start], _start_measurements,
                      _start_metadata}

      assert_receive {:telemetry_event, [:test, :span, :exception], exception_measurements,
                      exception_metadata}

      assert is_integer(exception_measurements.duration)
      assert exception_metadata.kind == :exit
      assert exception_metadata.reason == :test_exit
    end
  end

  describe "handle_event/4" do
    test "handles request stop event" do
      # Just ensure it doesn't crash
      assert :ok ==
               Telemetry.handle_event(
                 [:hermes, :request, :stop],
                 %{duration: 1_000_000},
                 %{status: 200, method: "GET", path: "/test", request_id: "abc123"},
                 nil
               )
    end

    test "handles request exception event" do
      assert :ok ==
               Telemetry.handle_event(
                 [:hermes, :request, :exception],
                 %{duration: 1_000_000},
                 %{request_id: "abc123", kind: :error, reason: "test error"},
                 nil
               )
    end

    test "handles llm stop event" do
      assert :ok ==
               Telemetry.handle_event(
                 [:hermes, :llm, :stop],
                 %{duration: 1_000_000},
                 %{model: "gemma", request_id: "abc123", result: {:ok, "response"}},
                 nil
               )
    end

    test "handles llm exception event" do
      assert :ok ==
               Telemetry.handle_event(
                 [:hermes, :llm, :exception],
                 %{duration: 1_000_000},
                 %{model: "gemma", request_id: "abc123", kind: :error, reason: "timeout"},
                 nil
               )
    end

    test "handles ollama request stop event" do
      assert :ok ==
               Telemetry.handle_event(
                 [:hermes, :ollama, :request, :stop],
                 %{duration: 1_000_000},
                 %{model: "gemma", status: 200},
                 nil
               )
    end

    test "handles ollama request exception event" do
      assert :ok ==
               Telemetry.handle_event(
                 [:hermes, :ollama, :request, :exception],
                 %{duration: 1_000_000},
                 %{model: "gemma", reason: "connection refused"},
                 nil
               )
    end

    test "handles unknown events gracefully" do
      assert :ok ==
               Telemetry.handle_event(
                 [:unknown, :event],
                 %{duration: 1_000_000},
                 %{},
                 nil
               )
    end
  end

  describe "get_request_id/1" do
    test "returns request ID from response header" do
      conn =
        Plug.Test.conn(:get, "/test")
        |> Plug.Conn.put_resp_header("x-request-id", "test-request-id")

      assert Telemetry.get_request_id(conn) == "test-request-id"
    end

    test "generates new request ID if none set" do
      conn = Plug.Test.conn(:get, "/test")

      request_id = Telemetry.get_request_id(conn)
      assert is_binary(request_id)
      assert String.length(request_id) > 0
    end
  end

  describe "set_logger_metadata/1" do
    test "sets logger metadata" do
      :ok = Telemetry.set_logger_metadata(request_id: "test-id", model: "gemma")

      metadata = Logger.metadata()
      assert Keyword.get(metadata, :request_id) == "test-id"
      assert Keyword.get(metadata, :model) == "gemma"
    end
  end

  describe "log_request/3" do
    test "logs request with metadata" do
      conn =
        Plug.Test.conn(:get, "/test")
        |> Plug.Conn.put_resp_header("x-request-id", "test-id")
        |> Map.put(:status, 200)

      # Just ensure it doesn't crash
      assert :ok == Telemetry.log_request(conn, 150)
    end

    test "logs with custom status" do
      conn =
        Plug.Test.conn(:get, "/test")
        |> Plug.Conn.put_resp_header("x-request-id", "test-id")

      assert :ok == Telemetry.log_request(conn, 150, status: 404)
    end
  end

  describe "log_llm_request/4" do
    test "logs successful LLM request" do
      assert :ok ==
               Telemetry.log_llm_request("gemma", 100, 500,
                 request_id: "test-id",
                 status: :ok,
                 response_length: 50
               )
    end

    test "logs failed LLM request" do
      assert :ok ==
               Telemetry.log_llm_request("gemma", 100, 500,
                 request_id: "test-id",
                 status: :error,
                 error: "timeout"
               )
    end
  end
end
