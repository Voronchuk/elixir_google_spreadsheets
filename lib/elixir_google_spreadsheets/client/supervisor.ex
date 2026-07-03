defmodule GSS.Client.Supervisor do
  @moduledoc """
  Supervisor to keep track of initialized Client, Limiter and Request processes.
  """

  use Supervisor
  alias GSS.{Client, Client.Limiter, Client.Request}

  @spec start_link(any()) :: Supervisor.on_start()
  def start_link(arg \\ []) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    config = Application.get_env(:elixir_google_spreadsheets, :client, [])
    limiter_args = Keyword.take(config, [:max_demand, :interval, :max_interval])

    children = [
      {Client, []},
      %{
        id: Limiter.Writer,
        start:
          {Limiter, :start_link,
           [
             limiter_args
             |> Keyword.put(:clients, [{Client, partition: :write}])
             |> Keyword.put(:name, Limiter.Writer)
           ]}
      },
      %{
        id: Limiter.Reader,
        start:
          {Limiter, :start_link,
           [
             limiter_args
             |> Keyword.put(:partition, :read)
             |> Keyword.put(:clients, [{Client, partition: :read}])
             |> Keyword.put(:name, Limiter.Reader)
           ]}
      }
    ]

    request_workers =
      for num <- 1..Keyword.get(config, :request_workers, 10),
          {limiter, name} <- [{Limiter.Writer, Request.Write}, {Limiter.Reader, Request.Read}] do
        name = :"#{name}#{num}"

        %{
          id: name,
          start: {Request, :start_link, [[name: name, limiters: [{limiter, max_demand: 1}]]]}
        }
      end

    Supervisor.init(children ++ request_workers, strategy: :one_for_one)
  end
end
