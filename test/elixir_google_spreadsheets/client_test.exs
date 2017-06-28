defmodule GSS.ClientTest do
  use ExUnit.Case, async: true

  defmodule TestConsumer do
    def start_link(producer) do
      GenStage.start_link(__MODULE__, {producer, self()})
    end

    def init({producer, owner}) do
      {:consumer, owner, subscribe_to: [producer]}
    end

    def handle_subscribe(:producer, _, _, state) do
      {:automatic, state}
    end

    def handle_events(events, _from, owner) do
      send(owner, {:received, events})
      {:noreply, [], owner}
    end
  end

  setup do
    {:ok, client} = GenStage.start_link(GSS.Client, :ok)

    [client: client]
  end

  test "add :write events to the queue and release them to client", %{client: client} do
    Task.async(fn -> GenStage.call(client, {:write, 1}) end)
    Task.async(fn -> GenStage.call(client, {:write, 2}) end)
    Task.async(fn -> GenStage.call(client, {:write, 3}) end)

    {:ok, _cons} = TestConsumer.start_link(client)

    assert_receive {:received, events}
    assert match?([{:write, _, 1}, {:write, _, 2}, {:write, _, 3}], events)

    :ok = GenStage.stop(client)
  end

end
