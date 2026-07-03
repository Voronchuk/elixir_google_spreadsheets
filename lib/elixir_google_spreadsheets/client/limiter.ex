defmodule GSS.Client.Limiter do
  @moduledoc """
  Model of Limiter request subscribed to Client with partition :write or :read

  This process is a ProducerConsumer for this GenStage pipeline.
  """

  use GenStage
  require Logger

  @type state :: %__MODULE__{
          max_demand: pos_integer(),
          max_interval: timeout(),
          producer: GenStage.from(),
          scheduled_at: integer() | nil,
          taken_events: pos_integer(),
          interval: timeout()
        }
  defstruct [:max_demand, :max_interval, :producer, :scheduled_at, :taken_events, :interval]

  @type options :: [
          name: atom(),
          max_demand: pos_integer() | nil,
          max_interval: timeout() | nil,
          interval: timeout() | nil,
          clients: [{atom(), keyword()} | atom()]
        ]

  @doc """
  Starts an limiter manager linked to the current process.

  If the event manager is successfully created and initialized, the function
  returns {:ok, pid}, where pid is the PID of the server. If a process with the
  specified server name already exists, the function returns {:error,
  {:already_started, pid}} with the PID of that process.

  ## Options
  * `:name` - used for name registration as described in the "Name
  registration" section of the module documentation
  * `:interval` - ask new events from producer after `:interval` milliseconds.
  * `:max_demand` - count of maximum requests per `:maximum_interval`
  * `:max_interval` - maximum time that allowed in `:max_demand` requests
  * `:clients` - list of clients with partition options. For example `[{GSS.Client, partition: :read}}]`.
  """
  @spec start_link(options()) :: GenServer.on_start()
  def start_link(options \\ []) do
    GenStage.start_link(__MODULE__, options, name: Keyword.get(options, :name))
  end

  ## Callbacks

  @impl true
  def init(args) do
    Logger.debug("init: #{inspect(args)}")

    state = %__MODULE__{
      max_demand: args[:max_demand] || 100,
      max_interval: args[:max_interval] || 1_000,
      interval: args[:interval] || 100,
      taken_events: 0,
      scheduled_at: nil
    }

    Process.send_after(self(), :ask, 0)

    {:producer_consumer, state, subscribe_to: args[:clients]}
  end

  @impl true
  # Set the subscription to manual to control when to ask for events
  def handle_subscribe(:producer, _options, from, state) do
    {:manual, Map.put(state, :producer, from)}
  end

  # Make the subscriptions to auto for consumers
  def handle_subscribe(:consumer, _, _, state) do
    {:automatic, state}
  end

  @impl true
  def handle_events(events, _from, state) do
    Logger.debug(fn -> "Limiter Handle events: #{inspect(events)}" end)

    state =
      state
      |> Map.update!(:taken_events, &(&1 + length(events)))
      |> schedule_counts()

    {:noreply, events, state}
  end

  @impl true
  def handle_demand(demand, state) when demand > 0 do
    {:noreply, [], state}
  end

  @impl true
  def handle_info(:ask, state) do
    {:noreply, [], ask_and_schedule(state)}
  end

  @doc """
  Check to reach limit.

  If limit not reached ask again after `:interval` timeout,
  otherwise ask after `:max_interval` timeout.
  """
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

  # take events more than max demand
  defp limited_events?(state) do
    state.taken_events >= state.max_demand
  end

  # check limit of interval
  defp interval_expired?(%__MODULE__{scheduled_at: nil}), do: false

  defp interval_expired?(%__MODULE__{scheduled_at: scheduled_at, max_interval: max_interval}) do
    System.monotonic_time(:millisecond) - scheduled_at >= max_interval
  end

  defp clear_counts(state) do
    %{state | taken_events: 0, scheduled_at: nil}
  end

  # set current timestamp to scheduled_at
  defp schedule_counts(%__MODULE__{scheduled_at: nil} = state) do
    %{state | scheduled_at: System.monotonic_time(:millisecond)}
  end

  defp schedule_counts(state), do: state
end
