defmodule GSS.Spreadsheet.Supervisor do
  @moduledoc """
  Supervisor to keep track of initialized spreadsheet processes.
  """

  use Supervisor

  @spec start_link() :: {:ok, pid}
  def start_link do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @spec spreadsheet(String.t(), Keyword.t()) :: {:ok, pid}
  def spreadsheet(spreadsheet_id, opts \\ []) do
    with \
      pid when is_pid(pid) <- GSS.Registry.spreadsheet_pid(spreadsheet_id),
      true <- Process.alive?(pid)
    do
      {:ok, pid}
    else
      _ ->
        {:ok, pid} = Supervisor.start_child(__MODULE__, [spreadsheet_id, opts])
        :ok = GSS.Registry.new_spreadsheet(spreadsheet_id, pid, opts)
        {:ok, pid}
    end
  end

  @spec init([]) :: {:ok, {:supervisor.sup_flags(), [Supervisor.Spec.spec()]}} | :ignore
  def init([]) do
    children = [
      worker(GSS.Spreadsheet, [], restart: :transient)
    ]

    supervise(children, strategy: :simple_one_for_one)
  end
end
