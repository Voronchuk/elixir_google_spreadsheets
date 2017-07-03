defmodule GSS.Client.LimiterTest do
    use ExUnit.Case, async: true

    alias GSS.Client.Limiter
    alias GSS.StubModules.{Producer, Consumer}

    setup context do
        {:ok, client} = Producer.start_link([])
        {:ok, limiter} = GenStage.start_link(
            Limiter,
            name: context.test,
            clients: [client],
            max_demand: 3, max_interval: 500, interval: 0
        )
        {:ok, _consumer} = Consumer.start_link(limiter)

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
