defmodule GSS.Spreadsheet.Supervisor do
    @moduledoc """
    Supervisor to keep track of initialized spreadsheet processes.
    """

    use Supervisor

    @spec start_link() :: {:ok, pid}
    def start_link do
        Supervisor.start_link(__MODULE__, [], name: __MODULE__)
    end

    @spec spreadsheet(String.t, atom() | nil) :: {:ok, pid}
    def spreadsheet(spreadsheet_id, name \\ nil) do
        {:ok, pid} = if is_nil(name) do
            Supervisor.start_child(__MODULE__, [spreadsheet_id])
        else
            Supervisor.start_child(__MODULE__, [spreadsheet_id, name])
        end
        :ok = GSS.Registry.new_spreadsheet(spreadsheet_id, pid)
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
