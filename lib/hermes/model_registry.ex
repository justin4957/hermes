defmodule Hermes.ModelRegistry do
  @moduledoc """
  GenServer that tracks active requests per model and enforces concurrency limits.

  The ModelRegistry maintains a count of in-flight requests for each model and
  provides mechanisms to acquire and release "slots" for processing. This enables
  per-model concurrency limiting to prevent resource exhaustion.

  ## Design

  - Uses an ETS table for fast concurrent reads of request counts
  - GenServer serializes state mutations (acquire/release) to prevent race conditions
  - Monitors calling processes to automatically release slots on crashes
  - Each model has its own concurrency limit from configuration

  ## Usage

      # Try to acquire a slot for a request
      case Hermes.ModelRegistry.acquire("gemma") do
        {:ok, ref} ->
          # Process request...
          Hermes.ModelRegistry.release(ref)
          {:ok, response}
        {:error, error} ->
          {:error, error}
      end

  ## Configuration

  Concurrency limits are read from the `:hermes, :models` config:

      config :hermes, :models,
        gemma: %{max_concurrency: 2, ...},
        llama3: %{max_concurrency: 1, ...}
  """

  use GenServer

  require Logger

  alias Hermes.Config
  alias Hermes.Error

  @type model_name :: String.t()
  @type slot_ref :: reference()

  # Default ETS table name (can be overridden per instance)
  @default_table __MODULE__

  # Client API

  @doc """
  Starts the ModelRegistry GenServer.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Attempts to acquire a slot for the given model.

  If the model is under its concurrency limit, increments the count and returns
  a reference that must be passed to `release/1` when done. If the limit is
  reached, returns a ConcurrencyLimitError.

  ## Parameters

    * `model` - Model name as string
    * `opts` - Options (optional)
      * `:registry` - Registry name (default: `Hermes.ModelRegistry`)

  ## Returns

    * `{:ok, ref}` - Successfully acquired slot, use ref to release
    * `{:error, ConcurrencyLimitError.t()}` - Model at capacity
  """
  @spec acquire(model_name(), keyword()) ::
          {:ok, slot_ref()} | {:error, Error.ConcurrencyLimitError.t()}
  def acquire(model, opts \\ []) do
    registry = Keyword.get(opts, :registry, __MODULE__)
    GenServer.call(registry, {:acquire, model, self()})
  end

  @doc """
  Releases a previously acquired slot.

  Must be called with the reference returned from `acquire/2` to decrement
  the active request count for the model.

  ## Parameters

    * `ref` - Reference returned from `acquire/2`
    * `opts` - Options (optional)
      * `:registry` - Registry name (default: `Hermes.ModelRegistry`)

  ## Returns

    * `:ok` - Slot released successfully
    * `{:error, :not_found}` - Reference not found (already released or invalid)
  """
  @spec release(slot_ref(), keyword()) :: :ok | {:error, :not_found}
  def release(ref, opts \\ []) do
    registry = Keyword.get(opts, :registry, __MODULE__)
    GenServer.call(registry, {:release, ref})
  end

  @doc """
  Returns the current request count for a model.

  ## Parameters

    * `model` - Model name as string
    * `opts` - Options (optional)
      * `:table` - ETS table name (default: `Hermes.ModelRegistry`)

  ## Returns

    * Current number of active requests for the model
  """
  @spec current_count(model_name(), keyword()) :: non_neg_integer()
  def current_count(model, opts \\ []) do
    table = Keyword.get(opts, :table, @default_table)

    case :ets.lookup(table, model) do
      [{^model, count}] -> count
      [] -> 0
    end
  end

  @doc """
  Returns counts for all models as a map.

  Useful for monitoring and status endpoints.
  """
  @spec all_counts(keyword()) :: %{model_name() => non_neg_integer()}
  def all_counts(opts \\ []) do
    table = Keyword.get(opts, :table, @default_table)

    table
    |> :ets.tab2list()
    |> Map.new()
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Create ETS table for fast concurrent reads
    :ets.new(@default_table, [:named_table, :public, :set, read_concurrency: true])

    # Initialize counts for all configured models
    for model <- Config.configured_models() do
      :ets.insert(@default_table, {Atom.to_string(model), 0})
    end

    state = %{
      # Map of ref => {model, pid, monitor_ref}
      active_slots: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:acquire, model, pid}, _from, state) do
    max_concurrency = Config.model_max_concurrency(model)
    current = current_count(model)

    cond do
      # Model not configured - no concurrency limit
      is_nil(max_concurrency) ->
        ref = make_ref()
        monitor_ref = Process.monitor(pid)
        :ets.update_counter(@default_table, model, {2, 1}, {model, 0})

        new_state = %{
          state
          | active_slots: Map.put(state.active_slots, ref, {model, pid, monitor_ref})
        }

        Logger.debug("Acquired slot for model",
          model: model,
          current: current + 1,
          max: max_concurrency
        )

        {:reply, {:ok, ref}, new_state}

      # Under limit - acquire slot
      current < max_concurrency ->
        ref = make_ref()
        monitor_ref = Process.monitor(pid)
        :ets.update_counter(@default_table, model, {2, 1}, {model, 0})

        new_state = %{
          state
          | active_slots: Map.put(state.active_slots, ref, {model, pid, monitor_ref})
        }

        Logger.debug("Acquired slot for model",
          model: model,
          current: current + 1,
          max: max_concurrency
        )

        {:reply, {:ok, ref}, new_state}

      # At or over limit - reject
      true ->
        Logger.warning("Concurrency limit reached",
          model: model,
          current: current,
          max: max_concurrency
        )

        error = Error.ConcurrencyLimitError.new(model, max_concurrency, current)
        {:reply, {:error, error}, state}
    end
  end

  @impl true
  def handle_call({:release, ref}, _from, state) do
    case Map.pop(state.active_slots, ref) do
      {nil, _state} ->
        {:reply, {:error, :not_found}, state}

      {{model, _pid, monitor_ref}, new_slots} ->
        Process.demonitor(monitor_ref, [:flush])
        :ets.update_counter(@default_table, model, {2, -1}, {model, 0})
        new_state = %{state | active_slots: new_slots}

        Logger.debug("Released slot for model",
          model: model,
          current: current_count(model)
        )

        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_info({:DOWN, monitor_ref, :process, pid, reason}, state) do
    # Find and release the slot for this crashed process
    case find_slot_by_monitor(state.active_slots, monitor_ref) do
      {ref, {model, ^pid, ^monitor_ref}} ->
        :ets.update_counter(@default_table, model, {2, -1}, {model, 0})
        new_state = %{state | active_slots: Map.delete(state.active_slots, ref)}

        Logger.warning("Auto-released slot due to process exit",
          model: model,
          pid: inspect(pid),
          reason: inspect(reason),
          current: current_count(model)
        )

        {:noreply, new_state}

      nil ->
        {:noreply, state}
    end
  end

  defp find_slot_by_monitor(active_slots, monitor_ref) do
    Enum.find(active_slots, fn {_ref, {_model, _pid, mref}} -> mref == monitor_ref end)
  end
end
