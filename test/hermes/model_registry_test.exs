defmodule Hermes.ModelRegistryTest do
  @moduledoc """
  Tests for the ModelRegistry GenServer.

  Note: These tests use the global ModelRegistry instance that's started
  by the application. Tests that modify state clean up after themselves.
  """
  use ExUnit.Case, async: false

  alias Hermes.Error.ConcurrencyLimitError
  alias Hermes.ModelRegistry

  describe "acquire/2 and release/2" do
    test "successfully acquires and releases slot for configured model" do
      # Acquire a slot
      assert {:ok, ref} = ModelRegistry.acquire("gemma")
      assert is_reference(ref)

      # Release it
      assert :ok = ModelRegistry.release(ref)
    end

    test "successfully acquires multiple slots up to limit" do
      # gemma has max_concurrency: 2
      {:ok, ref1} = ModelRegistry.acquire("gemma")
      {:ok, ref2} = ModelRegistry.acquire("gemma")

      assert is_reference(ref1)
      assert is_reference(ref2)
      assert ref1 != ref2

      # Clean up
      ModelRegistry.release(ref1)
      ModelRegistry.release(ref2)
    end

    test "returns error when concurrency limit reached" do
      # gemma has max_concurrency: 2, fill it up
      {:ok, ref1} = ModelRegistry.acquire("gemma")
      {:ok, ref2} = ModelRegistry.acquire("gemma")

      # Third request should fail
      assert {:error, %ConcurrencyLimitError{model: "gemma", max_concurrency: 2}} =
               ModelRegistry.acquire("gemma")

      # Clean up
      ModelRegistry.release(ref1)
      ModelRegistry.release(ref2)
    end

    test "allows new acquisition after release" do
      # Fill up gemma
      {:ok, ref1} = ModelRegistry.acquire("gemma")
      {:ok, ref2} = ModelRegistry.acquire("gemma")

      # Should be full
      assert {:error, %ConcurrencyLimitError{}} = ModelRegistry.acquire("gemma")

      # Release one
      :ok = ModelRegistry.release(ref1)

      # Should be able to acquire again
      {:ok, ref3} = ModelRegistry.acquire("gemma")

      # Clean up
      ModelRegistry.release(ref2)
      ModelRegistry.release(ref3)
    end

    test "returns error for invalid reference" do
      invalid_ref = make_ref()
      assert {:error, :not_found} = ModelRegistry.release(invalid_ref)
    end

    test "returns error for already released reference" do
      {:ok, ref} = ModelRegistry.acquire("gemma")
      :ok = ModelRegistry.release(ref)

      # Second release should fail
      assert {:error, :not_found} = ModelRegistry.release(ref)
    end

    test "different models have independent limits" do
      # Fill up gemma (max: 2)
      {:ok, ref1} = ModelRegistry.acquire("gemma")
      {:ok, ref2} = ModelRegistry.acquire("gemma")

      # llama3 should still work (max: 1)
      {:ok, ref3} = ModelRegistry.acquire("llama3")

      # Clean up
      ModelRegistry.release(ref1)
      ModelRegistry.release(ref2)
      ModelRegistry.release(ref3)
    end
  end

  describe "current_count/1" do
    test "returns count for model" do
      initial = ModelRegistry.current_count("phi")
      assert is_integer(initial)
      assert initial >= 0
    end

    test "increases after acquire and decreases after release" do
      initial = ModelRegistry.current_count("phi")
      {:ok, ref} = ModelRegistry.acquire("phi")
      assert ModelRegistry.current_count("phi") == initial + 1

      ModelRegistry.release(ref)
      assert ModelRegistry.current_count("phi") == initial
    end
  end

  describe "all_counts/0" do
    test "returns map of all model counts" do
      counts = ModelRegistry.all_counts()

      assert is_map(counts)
      # Should have entries for configured models
      assert Map.has_key?(counts, "gemma") or Map.has_key?(counts, "phi")
    end
  end
end
