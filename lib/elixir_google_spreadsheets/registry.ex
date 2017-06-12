defmodule GSS.Registry do
    @moduledoc """
    Google spreadsheets core authorization.
    Automatically updates access token after expiration.
    """

    use GenServer

    @typedoc """
    State of Google Cloud API :
        %{
            auth: %Goth.Token{
                expires: 1453356568,
                token: "ya29.cALlJ4HHWRvMkYB-WsAR-CZnexE459yA7QPqKg3nei1y2T7-iqmbcgxb8XrTATNn_Blim",
                type: "Bearer"
            }
        }
    """
    @type state :: map()

    @auth_scope "https://www.googleapis.com/auth/spreadsheets"


    @spec start_link() :: {:ok, pid}
    def start_link do
        initial_state = %{
            active_sheets: %{}
        }
        GenServer.start_link(__MODULE__, initial_state, name: __MODULE__)
    end

    @spec init(state) :: {:ok, state}
    def init(state) do
        {:ok, state}
    end


    @doc """
    Get account authorization token.
    """
    @spec token() :: String.t
    def token do
        GenServer.call(__MODULE__, :token)
    end

    @doc """
    Add or replace Google Spreadsheet in a registry.
    """
    @spec new_spreadsheet(String.t, pid, Keyword.t) :: :ok
    def new_spreadsheet(spreadsheet_id, pid, opts \\ []) do
        GenServer.call(__MODULE__, {:new_spreadsheet, spreadsheet_id, pid, opts})
    end

    @doc """
    Fetch Google Spreadsheet proccess by it's id in the registry.
    """
    @spec spreadsheet_pid(String.t, Keyword.t) :: pid
    def spreadsheet_pid(spreadsheet_id, opts \\ []) do
        GenServer.call(__MODULE__, {:spreadsheet_pid, spreadsheet_id, opts})
    end


    @doc """
    Get account authorization token, issue new token in case old has expired.
    """
    def handle_call(:token, _from, %{auth: %{
        token: token,
        expires: expires
    }} = state) do
        if (expires < :os.system_time(:seconds)) do
            new_state = Map.put(state, :auth, refresh_token())
            {:reply, new_state.auth.token, new_state}
        else
            {:reply, token, state}
        end
    end
    def handle_call(:token, _from, state) do
        new_state = Map.put(state, :auth, refresh_token())
        {:reply, new_state.auth.token, new_state}
    end
    
    @doc """
    Update :active_sheets registry record.
    """
    def handle_call(
        {:new_spreadsheet, spreadsheet_id, pid, opts},
        _from,
        %{active_sheets: active_sheets} = state
    ) when is_bitstring(spreadsheet_id) and is_pid(pid) do
        registry_id = id(spreadsheet_id, opts)
        new_active_sheets = Map.put(active_sheets, registry_id, pid)
        new_state = Map.put(state, :active_sheets, new_active_sheets)
        {:reply, :ok, new_state}
    end

    @doc """
    Get pid of sheet in :active_sheets registry.
    """
    def handle_call(
        {:spreadsheet_pid, spreadsheet_id, opts},
        _from,
        %{active_sheets: active_sheets} = state
    ) when is_bitstring(spreadsheet_id) do
        registry_id = id(spreadsheet_id, opts)
        {:reply, Map.get(active_sheets, registry_id, nil), state}
    end


    @spec refresh_token() :: map()
    defp refresh_token do
        {:ok, token} = Goth.Token.for_scope(@auth_scope)
        token
    end

    @spec id(String.t, Keyword.t) :: String.t
    defp id(spreadsheet_id, opts) do
        list_name = Keyword.get(opts, :list_name)
        if is_bitstring(list_name) do
            "#{spreadsheet_id}!#{list_name}"
        else
            spreadsheet_id
        end
    end
end
