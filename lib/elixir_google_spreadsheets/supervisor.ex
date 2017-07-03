defmodule GSS.Supervisor do
    @moduledoc """
    Supervisor tree to keep track of registry and spreadsheet supervisor.
    """

    use Supervisor

    @spec start_link() :: {:ok, pid()}
    def start_link do
        Supervisor.start_link(__MODULE__, [])
    end

    @spec init([]) :: {:ok, {:supervisor.sup_flags(), [Supervisor.Spec.spec()]}} | :ignore
    def init([]) do
        children = [
            worker(GSS.Registry, []),
            supervisor(GSS.Spreadsheet.Supervisor, []),
            supervisor(GSS.Client.Supervisor, [])
        ]

        supervise(children, strategy: :one_for_all)
    end
end
