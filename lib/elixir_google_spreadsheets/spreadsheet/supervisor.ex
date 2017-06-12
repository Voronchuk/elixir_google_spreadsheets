defmodule GSS.Spreadsheet.Supervisor do
    @moduledoc """
    Supervisor to keep track of initialized spreadsheet processes.
    """

    use Supervisor

    @spec start_link() :: {:ok, pid}
    def start_link do
        Supervisor.start_link(__MODULE__, [], name: __MODULE__)
    end

    @spec spreadsheet(String.t, Keyword.t) :: {:ok, pid}
    def spreadsheet(spreadsheet_id, opts \\ []) do
        {:ok, pid} = Supervisor.start_child(__MODULE__, [spreadsheet_id, opts])
        :ok = GSS.Registry.new_spreadsheet(spreadsheet_id, pid, opts)
        {:ok, pid}
    end

    @spec init([]) :: {:ok, pid}
    def init([]) do
        children = [
            worker(GSS.Spreadsheet, [], restart: :transient)
        ]

        supervise(children, strategy: :simple_one_for_one)
    end
end
