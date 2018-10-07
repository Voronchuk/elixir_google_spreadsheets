defmodule GSS.Client.Supervisor do
  @moduledoc """
  Supervisor to keep track of initialized Client, Limiter and Request processes.
  """

  use Supervisor
  alias GSS.{Client, Client.Limiter, Client.Request}

  @spec start_link() :: {:ok, pid}
  def start_link do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @spec init([]) :: {:ok, {:supervisor.sup_flags(), [Supervisor.Spec.spec()]}} | :ignore
  def init([]) do
    config = Application.fetch_env!(:elixir_google_spreadsheets, :client)
    limiter_args = Keyword.take(config, [:max_demand, :interval, :max_interval])

    children = [
      worker(Client, []),
      worker(
        Limiter,
        [
          limiter_args
          |> Keyword.put(:clients, [{Client, partition: :write}])
          |> Keyword.put(:name, Limiter.Writer)
        ],
        id: Limiter.Writer
      ),
      worker(
        Limiter,
        [
          limiter_args
          |> Keyword.put(:partition, :read)
          |> Keyword.put(:clients, [{Client, partition: :read}])
          |> Keyword.put(:name, Limiter.Reader)
        ],
        id: Limiter.Reader
      )
    ]

    request_workers =
      for num <- 1..Keyword.get(config, :request_workers, 10),
          {limiter, name} <- [{Limiter.Writer, Request.Write}, {Limiter.Reader, Request.Read}] do
        name = :"#{name}#{num}"

        worker(
          Request,
          [[name: name, limiters: [{limiter, max_demand: 1}]]],
          id: name
        )
      end

    supervise(children ++ request_workers, strategy: :one_for_one)
  end
end
