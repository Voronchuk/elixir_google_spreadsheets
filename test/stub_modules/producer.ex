defmodule GSS.StubModules.Producer do
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
