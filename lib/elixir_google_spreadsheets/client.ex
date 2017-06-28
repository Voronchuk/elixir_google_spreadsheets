defmodule GSS.Client do
  @moduledoc """

  This process is a Producer for this GenStage pipeline.

  """

  use GenStage

  defstruct [:queue]

  def start_link do
    GenStage.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def read(message, timeout \\ 30_000) do
    GenStage.call(__MODULE__, {:read, message}, timeout)
  end

  @doc """
  Adds an write event to the buffer queue.
  """
  def write(message, timeout \\ 50_000) do
    GenStage.call(__MODULE__, {:write, message}, timeout)
  end

  ## Callbacks

  def init(:ok) do
    state = %__MODULE__{
      queue: :queue.new()
    }
    {:producer, state}
  end

  # Adds an event
  def handle_call({:read, event}, from, state) do
    state = state
    |> Map.put(:queue, :queue.in({:read, from, event}, state.queue))

    {:noreply, [], state}
  end

  def handle_call({:write, message}, from, state) do
    state = state
    |> Map.put(:queue, :queue.in({:write, from, message}, state.queue))

    {:noreply, [], state}
  end

  # Gives events for the next stage to process when requested
  def handle_demand(demand, state) when demand > 0 do
    {events, queue} = take_from_queue(state.queue, demand, [])
    {:noreply, Enum.reverse(events), Map.put(state, :queue, queue)}
  end

  def handle_cancel(_reason, _from, state) do
    {:noreply, [], %{state | consumer: nil}}
  end

  defp take_from_queue(queue, 0, events) do
    {events, queue}
  end
  defp take_from_queue(queue, demand, events) do
    case :queue.out(queue) do
      {{:value, {kind, from, event}}, queue} ->
        GenStage.reply(from, :ok)
        take_from_queue(queue, demand - 1, [{kind, from, event} | events])
      {:empty, queue} ->
        take_from_queue(queue, 0, events)
    end
  end
end
