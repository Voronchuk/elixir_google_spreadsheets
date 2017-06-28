defmodule GSS.Client.LimiterTest do
  use ExUnit.Case, async: true

  alias GSS.Client.Limiter

  defmodule TestProducer do
    use GenStage

    def start_link(events) do
      GenStage.start_link(__MODULE__, {events, self()})
    end

    def init({events, owner}) do
      {:producer, {events, owner}}
    end

    def handle_demand(demand, {events, owner}) do
      {result, tail} = Enum.split(events, demand)

      send(owner, {:handled_demand, result, demand})
      {:noreply, result, {tail, owner}}
    end

    def handle_call({:add, new_events}, _from, {events, owner}) do
      {:reply, :ok, [], {events ++ new_events, owner}}
    end
  end

  setup do
    {:ok, client} = TestProducer.start_link([])
    {:ok, limiter} = GenStage.start_link(
      Limiter,
      client: [client], max_demand: 3, max_interval: 500, interval: 0
    )

    [client: client, limiter: limiter]
  end

  test "receive events in packs with limits", %{client: client, limiter: limiter} do
    GenStage.call(client, {:add, [1, 2, 3, 4, 5]})

    assert_receive {:handled_demand, [1, 2, 3], 3}
    refute_receive {:handled_demand, [4, 5], 3}, 400, "error waiting limits"
    assert_receive {:handled_demand, [4, 5], 3}, 200
    assert_receive {:handled_demand, [], 3}

    GenStage.call(client, {:add, [6, 7, 8, 9]})

    assert_receive {:handled_demand, [6, 7, 8], 3}
    refute_receive {:handled_demand, [9], 3}, 400, "error waiting limits"

    assert_receive {:handled_demand, [9], 3}, 200
    assert_receive {:handled_demand, [], 3}
  end

  test "receive events with limits", %{client: client} do
    GenStage.call(client, {:add, [1]})
    assert_receive {:handled_demand, [1], 3}

    GenStage.call(client, {:add, [2]})
    assert_receive {:handled_demand, [2], 3}

    GenStage.call(client, {:add, [3]})
    assert_receive {:handled_demand, [3], 3}

    GenStage.call(client, {:add, [4]})
    GenStage.call(client, {:add, [5]})

    refute_receive {:handled_demand, [4, 5], 3}, 400, "error waiting limits"
    assert_receive {:handled_demand, [4, 5], 3}, 200
  end

  test "receive events in expired interval", %{client: client, limiter: limiter} do
    GenStage.call(client, {:add, [1]})
    assert_receive {:handled_demand, [1], 3}
    Process.sleep(500)

    GenStage.call(client, {:add, [2]})
    assert_receive {:handled_demand, [2], 3}
  end

end
