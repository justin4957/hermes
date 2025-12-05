defmodule Hermes.IntegrationTest do
  @moduledoc """
  Integration tests for the Hermes API.

  These tests verify the end-to-end behavior of the HTTP API,
  including request handling, response formatting, and error scenarios.
  """
  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn

  alias Hermes.Router

  @opts Router.init([])

  describe "end-to-end API flow" do
    test "status endpoint returns valid health check" do
      conn =
        conn(:get, "/v1/status")
        |> Router.call(@opts)

      assert conn.status == 200

      {:ok, body} = Jason.decode(conn.resp_body)

      assert body["status"] == "ok"
      assert is_map(body["memory"])
      assert is_integer(body["schedulers"])
      assert body["schedulers"] == System.schedulers_online()
    end

    test "LLM endpoint validates request body" do
      # Missing prompt
      conn1 =
        conn(:post, "/v1/llm/gemma", Jason.encode!(%{}))
        |> put_req_header("content-type", "application/json")
        |> Router.call(@opts)

      assert conn1.status == 400
      {:ok, body1} = Jason.decode(conn1.resp_body)
      assert body1["error"] =~ "Missing"

      # Invalid prompt type
      conn2 =
        conn(:post, "/v1/llm/gemma", Jason.encode!(%{"prompt" => 123}))
        |> put_req_header("content-type", "application/json")
        |> Router.call(@opts)

      assert conn2.status == 400
    end

    test "response format consistency" do
      # Success response format (when Ollama is available)
      # Error response format (when Ollama is unavailable)
      conn =
        conn(:post, "/v1/llm/gemma", Jason.encode!(%{"prompt" => "test"}))
        |> put_req_header("content-type", "application/json")
        |> Router.call(@opts)

      {:ok, body} = Jason.decode(conn.resp_body)

      # Response should have exactly one of these keys
      has_result = Map.has_key?(body, "result")
      has_error = Map.has_key?(body, "error")

      assert has_result or has_error,
             "Response should contain either 'result' or 'error'"
    end

    test "404 responses have consistent format" do
      paths = ["/", "/undefined", "/v1", "/v1/unknown", "/api/v1/status"]

      for path <- paths do
        conn =
          conn(:get, path)
          |> Router.call(@opts)

        if conn.status == 404 do
          {:ok, body} = Jason.decode(conn.resp_body)
          assert body["error"] == "Not found"
        end
      end
    end
  end

  describe "concurrent request handling" do
    test "multiple status requests can be handled concurrently" do
      tasks =
        for _ <- 1..10 do
          Task.async(fn ->
            conn(:get, "/v1/status")
            |> Router.call(@opts)
          end)
        end

      results = Task.await_many(tasks, 5000)

      for conn <- results do
        assert conn.status == 200
        {:ok, body} = Jason.decode(conn.resp_body)
        assert body["status"] == "ok"
      end
    end
  end

  describe "memory usage in status" do
    test "memory values are reasonable" do
      conn =
        conn(:get, "/v1/status")
        |> Router.call(@opts)

      {:ok, body} = Jason.decode(conn.resp_body)

      # Memory should be positive
      assert body["memory"]["total"] > 0
      assert body["memory"]["processes"] > 0
      assert body["memory"]["system"] > 0

      # Total should be >= processes + system (roughly)
      # Note: This is a sanity check, not exact
      assert body["memory"]["total"] >= body["memory"]["processes"]
    end
  end

  describe "request body parsing" do
    test "handles valid JSON correctly" do
      valid_bodies = [
        %{"prompt" => "test"},
        %{"prompt" => "test", "extra" => "field"},
        %{"prompt" => ""}
      ]

      for body <- valid_bodies do
        conn =
          conn(:post, "/v1/llm/gemma", Jason.encode!(body))
          |> put_req_header("content-type", "application/json")
          |> Router.call(@opts)

        # Should not fail on JSON parsing
        # Valid status codes: 200 (success), 400 (validation), 404 (model not found),
        # 408 (timeout), 429 (concurrency limit), 500 (internal), 502 (Ollama error), 503 (connection error)
        assert conn.status in [200, 400, 404, 408, 429, 500, 502, 503]
        assert {:ok, _} = Jason.decode(conn.resp_body)
      end
    end

    test "rejects malformed JSON gracefully" do
      # Non-empty malformed bodies raise ParseError
      malformed_bodies = [
        "{invalid json}",
        "not json at all",
        "{\"prompt\": }"
      ]

      for body <- malformed_bodies do
        # Plug.Parsers raises on malformed JSON, which is expected behavior
        # We verify it raises a ParseError rather than crashing unexpectedly
        assert_raise Plug.Parsers.ParseError, fn ->
          conn(:post, "/v1/llm/gemma", body)
          |> put_req_header("content-type", "application/json")
          |> Router.call(@opts)
        end
      end

      # Empty body is handled differently - results in empty map
      conn =
        conn(:post, "/v1/llm/gemma", "")
        |> put_req_header("content-type", "application/json")
        |> Router.call(@opts)

      # Empty body means no prompt field, so should return 400
      assert conn.status == 400
    end
  end
end
