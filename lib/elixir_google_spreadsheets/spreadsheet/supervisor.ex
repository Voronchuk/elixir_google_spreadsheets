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

  @spec spreadsheet(String.t(), Keyword.t()) :: {:ok, pid} | {:error, term()}
  def spreadsheet(spreadsheet_id, opts \\ []) do
    key = GSS.Registry.key(spreadsheet_id, opts)

    case Registry.lookup(GSS.Registry, key) do
      [{pid, _value}] ->
        {:ok, pid}

      [] ->
        opts = Keyword.put(opts, :name, {:via, Registry, {GSS.Registry, key}})

        case DynamicSupervisor.start_child(__MODULE__, {GSS.Spreadsheet, {spreadsheet_id, opts}}) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          {:error, reason} -> {:error, reason}
        end
    end
  end
end
