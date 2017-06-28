defmodule GSS.Client.Limiter do
  @moduledoc """
  TODO:
  """

  use GenStage

  defstruct [:max_demand, :max_interval, :producer,
             :scheduled_at, :taked_events, :interval]

  def start_link(args \\ []) do
    GenStage.start_link(__MODULE__, args)
  end

  ## Callbacks

  def init(args) do
    state = %__MODULE__{
      max_demand: args[:max_demand] || 5,
      max_interval: args[:max_interval] || 5_000,
      interval: args[:interval] || 100,
      taked_events: 0,
      scheduled_at: nil
    }
    sync_offset = args[:sync_offset] || 0
    subscribe_to = args[:client] || [GSS.Client]

    Process.send_after(self(), :ask, sync_offset)

    {:consumer, state, subscribe_to: subscribe_to}
  end

  # Set the subscription to manual to control when to ask for events
  def handle_subscribe(:producer, _options, from, state) do
    {:manual, Map.put(state, :producer, from)}
  end

  # Make the subscriptions to auto for consumers
  def handle_subscribe(:consumer, _, _, state) do
    {:automatic, state}
  end

  def handle_events(events, _from, state) do
    Enum.map(events, fn
      {kind, from, message} -> message
      message -> message
    end)
    |> Enum.join(" ")
    |> IO.inspect(label: "#{Time.utc_now}..............handle_events")

    state = state
    |> Map.update!(:taked_events, &(&1 + length(events)))
    |> schedule_counts()

    {:noreply, [], state}
  end

  def handle_info(:ask, state) do
    {:noreply, [], ask_and_schedule(state)}
  end

  def ask_and_schedule(state) do
    cond do
      limited_events?(state) ->
        Process.send_after(self(), :ask, state.max_interval)
        clear_counts(state)

      interval_expired?(state) ->
        GenStage.ask(state.producer, state.max_demand)
        Process.send_after(self(), :ask, state.interval)
        clear_counts(state)

      true ->
        GenStage.ask(state.producer, state.max_demand)
        Process.send_after(self(), :ask, state.interval)

        schedule_counts(state)
    end
  end

  defp limited_events?(state) do
    state.taked_events >= state.max_demand
  end

  defp interval_expired?(%__MODULE__{scheduled_at: nil}), do: false
  defp interval_expired?(%__MODULE__{scheduled_at: scheduled_at, max_interval: max_interval}) do
    now = :erlang.timestamp()
    :timer.now_diff(now, scheduled_at) >= max_interval * 1000
  end

  defp clear_counts(state) do
    %{state | taked_events: 0, scheduled_at: nil}
  end

  defp schedule_counts(%__MODULE__{scheduled_at: nil} = state) do
    %{state | scheduled_at: :erlang.timestamp()}
  end
  defp schedule_counts(state), do: state
end
