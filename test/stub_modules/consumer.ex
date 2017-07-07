defmodule GSS.StubModules.Consumer do
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
