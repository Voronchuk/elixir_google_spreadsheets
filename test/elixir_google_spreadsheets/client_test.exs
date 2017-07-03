defmodule GSS.ClientTest do
  use ExUnit.Case, async: true

  alias GSS.Client.RequestParams
  alias GSS.StubModules.Consumer

  setup do
    {:ok, client} = GenStage.start_link(GSS.Client, :ok)

    client
    |> send_request(:get, 1)
    |> send_request(:post, 2)
    |> send_request(:get, 3)
    |> send_request(:put, 4)
    |> send_request(:get, 5)

    [client: client]
  end

  def send_request(client, method, num) do
    request = create_request(method, num)
    Task.async(fn -> GenStage.call(client, {:request, request}, 50_000) end)
    client
  end

  def create_request(method, num) do
    %RequestParams{method: method, url: "http://url/?n=#{num}"}
  end

  test "add request events to the queue and release them to read consumer", %{client: client} do
    {:ok, _cons} = Consumer.start_link({client, partition: :read})

    assert_receive {:received, [event1, event2, event3]}
    request1 = create_request(:get, 1)
    assert {:request, _, ^request1} = event1

    request2 = create_request(:get, 3)
    assert {:request, _, ^request2} = event2

    request3 = create_request(:get, 5)
    assert {:request, _, ^request3} = event3
  end

  test "add request events to the queue and release them to write consumer", %{client: client} do
    {:ok, _cons} = Consumer.start_link({client, partition: :write})

    assert_receive {:received, [event1, event2]}
    request1 = create_request(:post, 2)
    assert {:request, _, ^request1} = event1

    request2 = create_request(:put, 4)
    assert {:request, _, ^request2} = event2
  end

end
