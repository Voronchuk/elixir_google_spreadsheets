defmodule GSS.Registry do
  @moduledoc """
  In-memory registry of running spreadsheet processes.

  Maps a spreadsheet id (optionally scoped by `:list_name`) to the pid of the
  GenServer serving that sheet, so callers can look up or reuse an existing
  process. Authentication lives in `GSS.Auth`.
  """

  use GenServer

  @type state :: map()

  @spec start_link(any()) :: {:ok, pid}
  def start_link(_args \\ []) do
    initial_state = %{
      active_sheets: %{}
    }

    GenServer.start_link(__MODULE__, initial_state, name: __MODULE__)
  end

  @spec init(state) :: {:ok, state}
  def init(state) do
    {:ok, state}
  end

  @deprecated "Use GSS.Auth.token!/0 instead"
  defdelegate token, to: GSS.Auth, as: :token!

  @doc """
  Add or replace Google Spreadsheet in a registry.
  """
  @spec new_spreadsheet(String.t(), pid, Keyword.t()) :: :ok
  def new_spreadsheet(spreadsheet_id, pid, opts \\ []) do
    GenServer.call(__MODULE__, {:new_spreadsheet, spreadsheet_id, pid, opts})
  end

  @doc """
  Fetch Google Spreadsheet process by it's id in the registry.
  """
  @spec spreadsheet_pid(String.t(), Keyword.t()) :: pid | nil
  def spreadsheet_pid(spreadsheet_id, opts \\ []) do
    GenServer.call(__MODULE__, {:spreadsheet_pid, spreadsheet_id, opts})
  end

  # Update :active_sheets registry record.
  def handle_call(
        {:new_spreadsheet, spreadsheet_id, pid, opts},
        _from,
        %{active_sheets: active_sheets} = state
      )
      when is_bitstring(spreadsheet_id) and is_pid(pid) do
    registry_id = id(spreadsheet_id, opts)
    new_active_sheets = Map.put(active_sheets, registry_id, pid)
    new_state = Map.put(state, :active_sheets, new_active_sheets)
    {:reply, :ok, new_state}
  end

  # Get pid of sheet in :active_sheets registry.
  def handle_call(
        {:spreadsheet_pid, spreadsheet_id, opts},
        _from,
        %{active_sheets: active_sheets} = state
      )
      when is_bitstring(spreadsheet_id) do
    registry_id = id(spreadsheet_id, opts)
    {:reply, Map.get(active_sheets, registry_id, nil), state}
  end

  @spec id(String.t(), Keyword.t()) :: String.t()
  defp id(spreadsheet_id, opts) do
    list_name = Keyword.get(opts, :list_name)

    if is_bitstring(list_name) do
      "#{spreadsheet_id}!#{list_name}"
    else
      spreadsheet_id
    end
  end
end
