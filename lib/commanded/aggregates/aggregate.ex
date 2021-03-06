defmodule Commanded.Aggregates.Aggregate do
  @moduledoc """
  Process to provide access to a single event sourced aggregate root.

  Allows execution of commands against an aggregate and handles persistence of events to the event store.
  """
  use GenServer
  require Logger

  alias Commanded.Aggregates.Aggregate
  alias Commanded.Event.Mapper

  @read_event_batch_size 100

  defstruct aggregate_module: nil, aggregate_uuid: nil, aggregate_state: nil

  def start_link(aggregate_module, aggregate_uuid) do
    GenServer.start_link(__MODULE__, %Aggregate{
      aggregate_module: aggregate_module,
      aggregate_uuid: aggregate_uuid
    })
  end

  def init(%Aggregate{} = state) do
    # initial aggregate state is populated by loading events from event store
    GenServer.cast(self, {:populate_aggregate_state})

    {:ok, state}
  end

  @doc """
  Execute the given command against the aggregate, optionally providing a timeout.
  - `timeout` is an integer greater than zero which specifies how many milliseconds to wait for a reply, or the atom :infinity to wait indefinitely.
    The default value is 5000.

  Returns `:ok` on success, or `{:error, reason}` on failure
  """
  def execute(server, command, handler, timeout \\ 5_000) do
    GenServer.call(server, {:execute_command, command, handler}, timeout)
  end

  @doc """
  Access the aggregate's state
  """
  def aggregate_state(server) do
    GenServer.call(server, {:aggregate_state})
  end

  def aggregate_state(server, timeout) do
    GenServer.call(server, {:aggregate_state}, timeout)
  end

  @doc """
  Load any existing events for the aggregate from storage and repopulate the state using those events
  """
  def handle_cast({:populate_aggregate_state}, %Aggregate{} = state) do
    state = populate_aggregate_state(state)

    {:noreply, state}
  end

  @doc """
  Execute the given command, using the provided handler, against the current aggregate state
  """
  def handle_call({:execute_command, command, handler}, _from, %Aggregate{} = state) do
    {reply, state} = execute_command(command, handler, state)

    {:reply, reply, state}
  end

  def handle_call({:aggregate_state}, _from, %Aggregate{aggregate_state: aggregate_state} = state) do
    {:reply, aggregate_state, state}
  end

  defp populate_aggregate_state(%Aggregate{aggregate_module: aggregate_module, aggregate_uuid: aggregate_uuid} = state) do
    aggregate_state = case load_events(state, 1, []) do
      {:ok, events} ->
        # fetched all events, load aggregate
        aggregate_module.load(aggregate_uuid, map_from_recorded_events(events))

      {:error, :stream_not_found} ->
        # aggregate does not exist so create new
        aggregate_module.new(aggregate_uuid)
    end

    # events list should only include uncommitted events
    aggregate_state = %{aggregate_state | pending_events: []}

    %Aggregate{state | aggregate_state: aggregate_state}
  end

  # load events from the event store, in batches of 1,000 events, and create the aggregate
  defp load_events(%Aggregate{aggregate_uuid: aggregate_uuid} = state, start_version, events) do
    case EventStore.read_stream_forward(aggregate_uuid, start_version, @read_event_batch_size) do
      {:ok, batch} when length(batch) < @read_event_batch_size ->
        {:ok, events ++ batch}

      {:ok, batch} ->
        next_version = start_version + @read_event_batch_size

        # fetch next batch of events
        load_events(state, next_version, events ++ batch)

      {:error, :stream_not_found} = reply -> reply
    end
  end

  defp execute_command(command, handler, %Aggregate{aggregate_state: %{version: version} = aggregate_state} = state) do
    expected_version = version

    with {:ok, aggregate_state} <- handle_command(handler, aggregate_state, command),
         {:ok, aggregate_state} <- persist_events(aggregate_state, expected_version)
      do {:ok, %Aggregate{state | aggregate_state: aggregate_state}}
    else
      {:error, reason} = reply ->
        Logger.warn(fn -> "failed to execute command due to: #{inspect reason}" end)
        {reply, state}
    end
  end

  defp handle_command(handler, aggregate_state, command) do
    # command handler must return `{:ok, aggregate}` or `{:error, reason}`
    case handler.handle(aggregate_state, command) do
      {:ok, _aggregate} = reply -> reply
      {:error, _reason} = reply -> reply
    end
  end

  # no pending events to persist, do nothing
  defp persist_events(%{pending_events: []} = aggregate_state, _expected_version), do: {:ok, aggregate_state}

  defp persist_events(%{uuid: aggregate_uuid, pending_events: pending_events} = aggregate_state, expected_version) do
    correlation_id = UUID.uuid4
    event_data = Mapper.map_to_event_data(pending_events, correlation_id)

    :ok = EventStore.append_to_stream(aggregate_uuid, expected_version, event_data)

    # clear pending events after appending to stream
    {:ok, %{aggregate_state | pending_events: []}}
  end

  defp map_from_recorded_events(recorded_events) when is_list(recorded_events) do
    Mapper.map_from_recorded_events(recorded_events)
  end
end
