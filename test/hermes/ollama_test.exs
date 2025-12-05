defmodule Hermes.OllamaTest do
  use ExUnit.Case, async: true

  alias Hermes.Error
  alias Hermes.Ollama

  setup do
    bypass = Bypass.open()
    finch_name = :"TestFinch_#{System.unique_integer([:positive])}"
    start_supervised!({Finch, name: finch_name})
    base_url = "http://localhost:#{bypass.port}"

    {:ok, bypass: bypass, finch_name: finch_name, base_url: base_url}
  end

  describe "generate/3" do
    test "returns successful response when Ollama returns 200", ctx do
      expected_response = "Hello! I'm doing great, thank you for asking."

      Bypass.expect_once(ctx.bypass, "POST", "/api/generate", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded_body = Jason.decode!(body)

        assert decoded_body["model"] == "gemma"
        assert decoded_body["prompt"] == "Hello, how are you?"
        assert decoded_body["stream"] == false

        response_body =
          Jason.encode!(%{
            "model" => "gemma",
            "created_at" => "2024-01-01T00:00:00Z",
            "response" => expected_response,
            "done" => true
          })

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, response_body)
      end)

      result =
        Ollama.generate("gemma", "Hello, how are you?",
          base_url: ctx.base_url,
          finch_name: ctx.finch_name
        )

      assert {:ok, ^expected_response} = result
    end

    test "returns error for 404 HTTP status (model not found)", ctx do
      Bypass.expect_once(ctx.bypass, "POST", "/api/generate", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(404, "model 'invalid' not found")
      end)

      result =
        Ollama.generate("invalid", "test",
          base_url: ctx.base_url,
          finch_name: ctx.finch_name
        )

      assert {:error, %Error.ModelNotFoundError{model: "invalid"}} = result
    end

    test "returns error for 500 HTTP status", ctx do
      Bypass.expect_once(ctx.bypass, "POST", "/api/generate", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(500, "Internal server error")
      end)

      result =
        Ollama.generate("gemma", "test",
          base_url: ctx.base_url,
          finch_name: ctx.finch_name
        )

      assert {:error, %Error.OllamaError{status_code: 500}} = result
    end

    test "handles connection refused error", ctx do
      # Close the bypass to simulate connection refused
      Bypass.down(ctx.bypass)

      result =
        Ollama.generate("gemma", "test",
          base_url: ctx.base_url,
          finch_name: ctx.finch_name
        )

      assert {:error, %Error.ConnectionError{}} = result
    end

    @tag :skip
    test "handles timeout", ctx do
      # Note: This test is flaky due to timing issues and Bypass cleanup
      # The timeout behavior is tested through the Dispatcher tests instead
      Bypass.expect(ctx.bypass, "POST", "/api/generate", fn conn ->
        # Delay longer than timeout
        Process.sleep(500)

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{"response" => "delayed"}))
      end)

      result =
        Ollama.generate("gemma", "test",
          base_url: ctx.base_url,
          finch_name: ctx.finch_name,
          timeout: 50
        )

      assert {:error, message} = result
      assert message =~ "Request failed" or message =~ "timeout"
    end

    test "handles malformed JSON response", ctx do
      Bypass.expect_once(ctx.bypass, "POST", "/api/generate", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, "not valid json{}")
      end)

      result =
        Ollama.generate("gemma", "test",
          base_url: ctx.base_url,
          finch_name: ctx.finch_name
        )

      assert {:error, %Error.InternalError{message: message}} = result
      assert message =~ "decode"
    end

    test "handles response without 'response' field", ctx do
      Bypass.expect_once(ctx.bypass, "POST", "/api/generate", fn conn ->
        response_body =
          Jason.encode!(%{
            "model" => "gemma",
            "done" => true
          })

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, response_body)
      end)

      result =
        Ollama.generate("gemma", "test",
          base_url: ctx.base_url,
          finch_name: ctx.finch_name
        )

      assert {:error, %Error.InternalError{message: message}} = result
      assert message =~ "Unexpected response format"
    end

    test "sends correct content-type header", ctx do
      Bypass.expect_once(ctx.bypass, "POST", "/api/generate", fn conn ->
        assert Plug.Conn.get_req_header(conn, "content-type") == ["application/json"]

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{"response" => "ok"}))
      end)

      Ollama.generate("gemma", "test",
        base_url: ctx.base_url,
        finch_name: ctx.finch_name
      )
    end

    test "uses default timeout of 30000ms when not specified", ctx do
      # This test verifies the function doesn't error with default timeout
      Bypass.expect_once(ctx.bypass, "POST", "/api/generate", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{"response" => "ok"}))
      end)

      result =
        Ollama.generate("gemma", "test",
          base_url: ctx.base_url,
          finch_name: ctx.finch_name
        )

      assert {:ok, "ok"} = result
    end

    test "handles empty response body from model", ctx do
      Bypass.expect_once(ctx.bypass, "POST", "/api/generate", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{"response" => ""}))
      end)

      result =
        Ollama.generate("gemma", "test",
          base_url: ctx.base_url,
          finch_name: ctx.finch_name
        )

      assert {:ok, ""} = result
    end

    test "handles unicode in prompt and response", ctx do
      unicode_prompt = "Explain 你好世界 and émojis 🎉"
      unicode_response = "你好世界 means 'Hello World' in Chinese! 🌍"

      Bypass.expect_once(ctx.bypass, "POST", "/api/generate", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded_body = Jason.decode!(body)

        assert decoded_body["prompt"] == unicode_prompt

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{"response" => unicode_response}))
      end)

      result =
        Ollama.generate("gemma", unicode_prompt,
          base_url: ctx.base_url,
          finch_name: ctx.finch_name
        )

      assert {:ok, ^unicode_response} = result
    end
  end
end
