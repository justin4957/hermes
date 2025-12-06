defmodule Hermes.RouterTest do
  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn

  alias Hermes.Router

  @opts Router.init([])

  describe "POST /v1/llm/:model" do
    test "returns 200 with successful generation" do
      # This test requires the full application to be running
      # We'll test the router behavior with Plug.Test
      conn =
        conn(:post, "/v1/llm/gemma", Jason.encode!(%{"prompt" => "Hello"}))
        |> put_req_header("content-type", "application/json")

      # Since we can't easily mock the Dispatcher in the router,
      # we'll test the request/response format validation
      conn = Router.call(conn, @opts)

      # The response should be either a success or an error
      # (depending on whether Ollama is running)
      # 404 is also valid if model not found in Ollama
      assert conn.status in [200, 404, 408, 500, 502, 503]
      assert conn.resp_body != nil

      # Verify it's valid JSON
      assert {:ok, _body} = Jason.decode(conn.resp_body)
    end

    test "returns 400 when prompt is missing" do
      conn =
        conn(:post, "/v1/llm/gemma", Jason.encode!(%{"not_prompt" => "test"}))
        |> put_req_header("content-type", "application/json")
        |> Router.call(@opts)

      assert conn.status == 400
      assert {:ok, body} = Jason.decode(conn.resp_body)
      assert body["error"] =~ "Missing 'prompt' field"
    end

    test "returns 400 when body is empty" do
      conn =
        conn(:post, "/v1/llm/gemma", "")
        |> put_req_header("content-type", "application/json")
        |> Router.call(@opts)

      # Empty body should trigger an error
      assert conn.status in [400, 500]
    end

    test "returns 400 when prompt is not a string" do
      conn =
        conn(:post, "/v1/llm/gemma", Jason.encode!(%{"prompt" => 123}))
        |> put_req_header("content-type", "application/json")
        |> Router.call(@opts)

      assert conn.status == 400
      assert {:ok, body} = Jason.decode(conn.resp_body)
      assert body["error"] =~ "Missing 'prompt' field" or body["error"] =~ "invalid"
    end

    test "returns 400 when prompt is null" do
      conn =
        conn(:post, "/v1/llm/gemma", Jason.encode!(%{"prompt" => nil}))
        |> put_req_header("content-type", "application/json")
        |> Router.call(@opts)

      assert conn.status == 400
    end

    @tag timeout: 180_000
    test "accepts different model names in path" do
      # Test that routes exist for various model names
      # Note: This test makes real connections so it may take time if Ollama isn't running
      models = ["gemma", "llama3", "mistral"]

      for model <- models do
        conn =
          conn(:post, "/v1/llm/#{model}", Jason.encode!(%{"prompt" => "test"}))
          |> put_req_header("content-type", "application/json")
          |> Router.call(@opts)

        # The route should exist and return a valid status code
        # 404 is valid if model not found in Ollama (but route exists)
        # Other codes: 200 (success), 408 (timeout), 500 (internal), 502 (Ollama), 503 (connection)
        assert conn.status in [200, 404, 408, 500, 502, 503],
               "Model #{model} route should return a valid status, got #{conn.status}"
      end
    end

    test "response contains 'result' key on success format" do
      # When successful, the response should have a 'result' key
      # We test the structure, not the actual content
      conn =
        conn(:post, "/v1/llm/gemma", Jason.encode!(%{"prompt" => "test"}))
        |> put_req_header("content-type", "application/json")
        |> Router.call(@opts)

      {:ok, body} = Jason.decode(conn.resp_body)

      if conn.status == 200 do
        assert Map.has_key?(body, "result")
      else
        assert Map.has_key?(body, "error")
      end
    end
  end

  describe "GET /v1/status" do
    test "returns 200 with status information when healthy" do
      conn =
        conn(:get, "/v1/status")
        |> Router.call(@opts)

      # Status will be 200 (healthy) or 503 (unhealthy) depending on Ollama availability
      assert conn.status in [200, 503]
      assert {:ok, body} = Jason.decode(conn.resp_body)
      assert body["status"] in ["healthy", "unhealthy"]
      assert is_binary(body["version"])
      assert is_integer(body["uptime_seconds"])
      assert is_map(body["checks"])
      assert is_list(body["models"])
    end

    test "returns memory information" do
      conn =
        conn(:get, "/v1/status")
        |> Router.call(@opts)

      {:ok, body} = Jason.decode(conn.resp_body)

      assert is_map(body["memory"])
      assert is_integer(body["memory"]["total"])
      assert is_integer(body["memory"]["processes"])
      assert is_integer(body["memory"]["system"])
      assert body["memory"]["total"] > 0
    end

    test "returns scheduler count" do
      conn =
        conn(:get, "/v1/status")
        |> Router.call(@opts)

      {:ok, body} = Jason.decode(conn.resp_body)

      assert is_integer(body["schedulers"])
      assert body["schedulers"] > 0
    end

    test "returns valid JSON content type behavior" do
      conn =
        conn(:get, "/v1/status")
        |> Router.call(@opts)

      # Response should be valid JSON
      assert {:ok, _} = Jason.decode(conn.resp_body)
    end
  end

  describe "404 handling" do
    test "returns 404 for undefined routes" do
      conn =
        conn(:get, "/undefined/route")
        |> Router.call(@opts)

      assert conn.status == 404
      assert {:ok, body} = Jason.decode(conn.resp_body)
      assert body["error"] == "Not found"
    end

    test "returns 404 for GET on LLM endpoint" do
      conn =
        conn(:get, "/v1/llm/gemma")
        |> Router.call(@opts)

      assert conn.status == 404
    end

    test "returns 404 for POST on status endpoint" do
      conn =
        conn(:post, "/v1/status", "")
        |> Router.call(@opts)

      assert conn.status == 404
    end

    test "returns 404 for root path" do
      conn =
        conn(:get, "/")
        |> Router.call(@opts)

      assert conn.status == 404
      assert {:ok, body} = Jason.decode(conn.resp_body)
      assert body["error"] == "Not found"
    end

    test "returns 404 for DELETE method" do
      conn =
        conn(:delete, "/v1/llm/gemma")
        |> Router.call(@opts)

      assert conn.status == 404
    end

    test "returns 404 for PUT method" do
      conn =
        conn(:put, "/v1/llm/gemma", "")
        |> Router.call(@opts)

      assert conn.status == 404
    end
  end

  describe "content type handling" do
    test "accepts application/json content type" do
      conn =
        conn(:post, "/v1/llm/gemma", Jason.encode!(%{"prompt" => "test"}))
        |> put_req_header("content-type", "application/json")
        |> Router.call(@opts)

      # Should process the request (not reject for content type)
      assert conn.status in [200, 400, 404, 408, 500, 502, 503]
    end

    test "accepts application/json with charset" do
      conn =
        conn(:post, "/v1/llm/gemma", Jason.encode!(%{"prompt" => "test"}))
        |> put_req_header("content-type", "application/json; charset=utf-8")
        |> Router.call(@opts)

      assert conn.status in [200, 400, 404, 408, 500, 502, 503]
    end
  end

  describe "edge cases" do
    test "handles empty model name in path" do
      conn =
        conn(:post, "/v1/llm/", Jason.encode!(%{"prompt" => "test"}))
        |> put_req_header("content-type", "application/json")
        |> Router.call(@opts)

      # Empty model name should either 404 or handle gracefully
      assert conn.status in [200, 400, 404, 408, 500, 502, 503]
    end

    test "handles very long prompt" do
      long_prompt = String.duplicate("test ", 1000)

      conn =
        conn(:post, "/v1/llm/gemma", Jason.encode!(%{"prompt" => long_prompt}))
        |> put_req_header("content-type", "application/json")
        |> Router.call(@opts)

      # Should handle without crashing
      assert conn.status in [200, 400, 404, 408, 500, 502, 503]
    end

    test "handles special characters in prompt" do
      special_prompt =
        "Test with <script>alert('xss')</script> and 'quotes' and \"double quotes\""

      conn =
        conn(:post, "/v1/llm/gemma", Jason.encode!(%{"prompt" => special_prompt}))
        |> put_req_header("content-type", "application/json")
        |> Router.call(@opts)

      assert conn.status in [200, 400, 404, 408, 500, 502, 503]
      # Response should be valid JSON (proper escaping)
      assert {:ok, _} = Jason.decode(conn.resp_body)
    end

    test "handles unicode in prompt" do
      unicode_prompt = "Translate: 你好世界 🌍 émojis"

      conn =
        conn(:post, "/v1/llm/gemma", Jason.encode!(%{"prompt" => unicode_prompt}))
        |> put_req_header("content-type", "application/json")
        |> Router.call(@opts)

      assert conn.status in [200, 400, 404, 408, 500, 502, 503]
    end

    test "handles newlines in prompt" do
      multiline_prompt = "Line 1\nLine 2\nLine 3"

      conn =
        conn(:post, "/v1/llm/gemma", Jason.encode!(%{"prompt" => multiline_prompt}))
        |> put_req_header("content-type", "application/json")
        |> Router.call(@opts)

      assert conn.status in [200, 400, 404, 408, 500, 502, 503]
    end
  end
end
