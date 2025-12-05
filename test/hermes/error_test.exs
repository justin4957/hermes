defmodule Hermes.ErrorTest do
  use ExUnit.Case, async: true

  alias Hermes.Error

  alias Hermes.Error.{
    ConcurrencyLimitError,
    ConnectionError,
    InternalError,
    ModelNotConfiguredError,
    ModelNotFoundError,
    OllamaError,
    TimeoutError,
    ValidationError
  }

  describe "ValidationError" do
    test "creates error with message" do
      error = ValidationError.new("Invalid input")

      assert error.message == "Invalid input"
      assert error.field == nil
      assert error.details == nil
    end

    test "creates error with field" do
      error = ValidationError.new("Field required", field: "prompt")

      assert error.message == "Field required"
      assert error.field == "prompt"
    end

    test "http_status returns 400" do
      error = ValidationError.new("test")
      assert Error.http_status(error) == 400
    end

    test "type returns :validation_error" do
      error = ValidationError.new("test")
      assert Error.type(error) == :validation_error
    end

    test "to_map includes field when present" do
      error = ValidationError.new("Missing field", field: "prompt")
      map = Error.to_map(error)

      assert map.error == "Missing field"
      assert map.type == "validation_error"
      assert map.field == "prompt"
    end
  end

  describe "ModelNotConfiguredError" do
    test "creates error with model name" do
      error = ModelNotConfiguredError.new("unknown")

      assert error.model == "unknown"
      assert error.message =~ "unknown"
      assert error.message =~ "not configured"
      assert error.available_models == []
    end

    test "creates error with available models" do
      error = ModelNotConfiguredError.new("unknown", [:gemma, :llama3])

      assert error.model == "unknown"
      assert error.available_models == [:gemma, :llama3]
      assert error.message =~ "gemma"
      assert error.message =~ "llama3"
    end

    test "http_status returns 404" do
      error = ModelNotConfiguredError.new("test")
      assert Error.http_status(error) == 404
    end

    test "type returns :model_not_configured" do
      error = ModelNotConfiguredError.new("test")
      assert Error.type(error) == :model_not_configured
    end

    test "to_map includes model and available_models" do
      error = ModelNotConfiguredError.new("unknown", [:gemma, :llama3])
      map = Error.to_map(error)

      assert map.type == "model_not_configured"
      assert map.model == "unknown"
      assert map.available_models == ["gemma", "llama3"]
    end

    test "to_map excludes available_models when empty" do
      error = ModelNotConfiguredError.new("unknown", [])
      map = Error.to_map(error)

      assert map.type == "model_not_configured"
      assert map.model == "unknown"
      refute Map.has_key?(map, :available_models)
    end
  end

  describe "ModelNotFoundError" do
    test "creates error with model name" do
      error = ModelNotFoundError.new("gemma")

      assert error.model == "gemma"
      assert error.message =~ "gemma"
      assert error.message =~ "not found"
    end

    test "http_status returns 404" do
      error = ModelNotFoundError.new("test")
      assert Error.http_status(error) == 404
    end

    test "type returns :model_not_found" do
      error = ModelNotFoundError.new("test")
      assert Error.type(error) == :model_not_found
    end

    test "to_map includes model" do
      error = ModelNotFoundError.new("llama3")
      map = Error.to_map(error)

      assert map.type == "model_not_found"
      assert map.model == "llama3"
    end
  end

  describe "ConcurrencyLimitError" do
    test "creates error with model and limits" do
      error = ConcurrencyLimitError.new("gemma", 2, 2)

      assert error.model == "gemma"
      assert error.max_concurrency == 2
      assert error.current_count == 2
      assert error.message =~ "gemma"
      assert error.message =~ "capacity"
      assert error.message =~ "2/2"
    end

    test "http_status returns 429" do
      error = ConcurrencyLimitError.new("gemma", 2, 2)
      assert Error.http_status(error) == 429
    end

    test "type returns :concurrency_limit" do
      error = ConcurrencyLimitError.new("gemma", 2, 2)
      assert Error.type(error) == :concurrency_limit
    end

    test "to_map includes all concurrency info" do
      error = ConcurrencyLimitError.new("gemma", 2, 2)
      map = Error.to_map(error)

      assert map.type == "concurrency_limit"
      assert map.model == "gemma"
      assert map.max_concurrency == 2
      assert map.current == 2
    end
  end

  describe "TimeoutError" do
    test "creates error with timeout" do
      error = TimeoutError.new(5000)

      assert error.timeout_ms == 5000
      assert error.message =~ "5000ms"
    end

    test "http_status returns 408" do
      error = TimeoutError.new(1000)
      assert Error.http_status(error) == 408
    end

    test "type returns :timeout" do
      error = TimeoutError.new(1000)
      assert Error.type(error) == :timeout
    end

    test "to_map includes timeout_ms" do
      error = TimeoutError.new(3000)
      map = Error.to_map(error)

      assert map.type == "timeout"
      assert map.timeout_ms == 3000
    end
  end

  describe "OllamaError" do
    test "creates error with message" do
      error = OllamaError.new("Service error")

      assert error.message == "Service error"
      assert error.status_code == nil
    end

    test "creates error with status code" do
      error = OllamaError.new("Server error", status_code: 500)

      assert error.message == "Server error"
      assert error.status_code == 500
    end

    test "http_status returns 502" do
      error = OllamaError.new("test")
      assert Error.http_status(error) == 502
    end

    test "type returns :ollama_error" do
      error = OllamaError.new("test")
      assert Error.type(error) == :ollama_error
    end

    test "to_map includes upstream_status when present" do
      error = OllamaError.new("Error", status_code: 503)
      map = Error.to_map(error)

      assert map.type == "ollama_error"
      assert map.upstream_status == 503
    end
  end

  describe "InternalError" do
    test "creates error with message" do
      error = InternalError.new("Something went wrong")

      assert error.message == "Something went wrong"
      assert error.reason == nil
    end

    test "creates error with reason" do
      error = InternalError.new("Failed", %RuntimeError{message: "oops"})

      assert error.message == "Failed"
      assert error.reason == %RuntimeError{message: "oops"}
    end

    test "http_status returns 500" do
      error = InternalError.new("test")
      assert Error.http_status(error) == 500
    end

    test "type returns :internal_error" do
      error = InternalError.new("test")
      assert Error.type(error) == :internal_error
    end
  end

  describe "ConnectionError" do
    test "creates error with message" do
      error = ConnectionError.new("Cannot connect")

      assert error.message == "Cannot connect"
      assert error.url == nil
    end

    test "creates error with url" do
      error = ConnectionError.new("Connection refused", url: "http://localhost:11434")

      assert error.message == "Connection refused"
      assert error.url == "http://localhost:11434"
    end

    test "http_status returns 503" do
      error = ConnectionError.new("test")
      assert Error.http_status(error) == 503
    end

    test "type returns :connection_error" do
      error = ConnectionError.new("test")
      assert Error.type(error) == :connection_error
    end

    test "to_map includes url when present" do
      error = ConnectionError.new("Error", url: "http://test:1234")
      map = Error.to_map(error)

      assert map.type == "connection_error"
      assert map.url == "http://test:1234"
    end
  end

  describe "http_status/1" do
    test "returns correct status for each error type" do
      assert Error.http_status(ValidationError.new("test")) == 400
      assert Error.http_status(ModelNotFoundError.new("test")) == 404
      assert Error.http_status(TimeoutError.new(100)) == 408
      assert Error.http_status(InternalError.new("test")) == 500
      assert Error.http_status(OllamaError.new("test")) == 502
      assert Error.http_status(ConnectionError.new("test")) == 503
    end

    test "returns 500 for unknown error types" do
      assert Error.http_status("string error") == 500
      assert Error.http_status(%{unknown: "error"}) == 500
    end
  end

  describe "message/1" do
    test "returns message from error struct" do
      error = TimeoutError.new(5000)
      assert Error.message(error) =~ "5000ms"
    end

    test "returns default for unknown types" do
      assert Error.message(:unknown) == "An unexpected error occurred"
    end
  end

  describe "to_map/1" do
    test "handles string errors" do
      map = Error.to_map("Something failed")

      assert map.error == "Something failed"
      assert map.type == "unknown_error"
    end

    test "handles unknown types" do
      map = Error.to_map(:unknown)

      assert map.error == "An unexpected error occurred"
      assert map.type == "unknown_error"
    end
  end

  describe "from_string/2" do
    test "converts HTTP 404 to ModelNotFoundError" do
      error = Error.from_string("HTTP 404: model not found", model: "gemma")

      assert %ModelNotFoundError{} = error
      assert error.model == "gemma"
    end

    test "converts timeout string to TimeoutError" do
      error = Error.from_string("Request timeout after 5000ms")

      assert %TimeoutError{} = error
      assert error.timeout_ms == 5000
    end

    test "converts HTTP 5xx to OllamaError" do
      error = Error.from_string("HTTP 500: internal server error")

      assert %OllamaError{} = error
      assert error.status_code == 500
    end

    test "converts connection errors to ConnectionError" do
      error = Error.from_string("Request failed: connection refused", url: "http://test:1234")

      assert %ConnectionError{} = error
      assert error.url == "http://test:1234"
    end

    test "converts task failures to InternalError" do
      error = Error.from_string("Task execution failed: some reason")

      assert %InternalError{} = error
    end

    test "converts task exits to InternalError" do
      error = Error.from_string("Task exit: {:shutdown, :brutal_kill}")

      assert %InternalError{} = error
    end

    test "converts unknown strings to InternalError" do
      error = Error.from_string("Some unknown error")

      assert %InternalError{} = error
      assert error.message == "Some unknown error"
    end
  end
end
