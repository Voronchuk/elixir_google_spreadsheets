defmodule GSS.Client.Supervisor do
    use Supervisor

    @config Application.fetch_env!(:elixir_google_spreadsheets, :client)

    @spec start_link() :: {:ok, pid}
    def start_link do
       Supervisor.start_link(__MODULE__, [],  name: __MODULE__)
    end

    @spec init([]) :: {:ok, pid}
    def init([]) do
        limiter_args = Keyword.take(@config, [:max_demand, :interval, :max_interval])
        children = [
            worker(GSS.Client, []),
            worker(GSS.Client.Limiter, [
                limiter_args
                |> Keyword.put(:clients, [{GSS.Client, partition: :write}])
                |> Keyword.put(:name, GSS.Client.LimiterWriter)
            ], id: LimiterWriter, restart: :transient),
            worker(GSS.Client.Limiter, [
                limiter_args
                |> Keyword.put(:partition, :read)
                |> Keyword.put(:clients, [{GSS.Client, partition: :read}])
                |> Keyword.put(:name, GSS.Client.LimiterReader)
            ], id: LimiterReader, restart: :transient)
        ]

        request_workers =
            for num <- 1..Keyword.get(@config, :request_workers, 10),
            limiter <- [GSS.Client.LimiterWriter, GSS.Client.LimiterReader]
            do
                worker(GSS.Client.Request, [[
                limiters: [{limiter, max_demand: 1}]
                ]], id: :"#{limiter}#{num}", restart: :transient)
            end

        supervise(children ++ request_workers, strategy: :one_for_one)
    end
end
