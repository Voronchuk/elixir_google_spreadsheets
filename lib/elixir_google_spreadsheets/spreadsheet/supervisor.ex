defmodule GSS.Spreadsheet.Supervisor do
  @moduledoc """
  Supervisor to keep track of initialized spreadsheet processes.
  """

  use DynamicSupervisor

  @spec start_link(any()) :: {:ok, pid}
  def start_link(_args \\ []) do
    DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @spec init([]) :: {:ok, DynamicSupervisor.sup_flags()}
  def init([]) do
    DynamicSupervisor.init(strategy: :one_for_one)
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
        spec = %{
          id: GSS.Spreadsheet,
          start: {GSS.Spreadsheet, :start_link, [spreadsheet_id, opts]},
          shutdown: 5_000,
          restart: :transient,
          type: :worker
        }

        {:ok, pid} = DynamicSupervisor.start_child(__MODULE__, spec)
        :ok = GSS.Registry.new_spreadsheet(spreadsheet_id, pid, opts)
        {:ok, pid}
    end
  end
end
