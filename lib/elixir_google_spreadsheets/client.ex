defmodule GSS.Client do
  @moduledoc """

  This process is a Producer for this GenStage pipeline.

  """

  use GenStage
  require Logger

  defmodule RequestParams do
    defstruct [method: nil, url: nil, body: "", headers: [], options: []]
  end

  def start_link do
    GenStage.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc """
  Issues an HTTP request with the given method to the given url.
  """
  def request(method, url, body \\ "", headers \\ [], options \\ []) do
    timeout = :timer.seconds(60*60)
    request = %RequestParams{
      method: method,
      url: url,
      body: body,
      headers: headers,
      options: options
    }
    GenStage.call(__MODULE__, {:request, request}, timeout)
  end

  def request_async(method, url, body \\ "", headers \\ [], options \\ []) do
    Task.async(GSS.Client, :request, [method, url, body, headers, options])
  end

  ## Callbacks

  def init(:ok) do
    dispatcer = {GenStage.PartitionDispatcher, partitions: [:write, :read], hash: &dispatcher_hash(&1)}
    {:producer, :queue.new(), dispatcher: dispatcer}
  end

  # Adds an event
  def handle_call({:request, request}, from, queue) do
    updated_queue  = :queue.in({:request, from, request}, queue)
    {:noreply, [], updated_queue}
  end

  # Gives events for the next stage to process when requested
  def handle_demand(demand, queue) when demand > 0 do
    {events, updated_queue} = take_from_queue(queue, demand, [])
    {:noreply, Enum.reverse(events), updated_queue}
  end

  defp take_from_queue(queue, 0, events) do
    {events, queue}
  end
  defp take_from_queue(queue, demand, events) do
    case :queue.out(queue) do
      {{:value, {kind, from, event}}, queue} ->
        take_from_queue(queue, demand - 1, [{kind, from, event} | events])
      {:empty, queue} ->
        take_from_queue(queue, 0, events)
    end
  end

  def dispatcher_hash({:request, from, request} = event) do
    case request.method do
      :get -> {event, :read}
      _ -> {event, :write}
    end
  end
end
