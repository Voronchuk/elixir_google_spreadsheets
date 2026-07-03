defmodule GSS.Registry do
  @moduledoc """
  Thin facade over Elixir's `Registry` for locating running spreadsheet processes.

  The registry process itself is started in `GSS.start/2` as
  `{Registry, keys: :unique, name: GSS.Registry}` — the module name doubles as the
  registry's process name. Spreadsheet GenServers register themselves via
  `{:via, Registry, {GSS.Registry, key/2}}`, so this module only builds the lookup
  key and resolves it back to a pid. Authentication lives in `GSS.Auth`.
  """

  @deprecated "Use GSS.Auth.token!/0 instead"
  defdelegate token, to: GSS.Auth, as: :token!

  @doc """
  Fetch a Google Spreadsheet process by its id (optionally scoped by `:list_name`).
  """
  @spec spreadsheet_pid(String.t(), Keyword.t()) :: pid | nil
  def spreadsheet_pid(spreadsheet_id, opts \\ []) do
    case Registry.lookup(__MODULE__, key(spreadsheet_id, opts)) do
      [{pid, _value}] -> pid
      [] -> nil
    end
  end

  @doc """
  Build the registry key for a spreadsheet id, scoped by `:list_name` when present.
  """
  @spec key(String.t(), Keyword.t()) :: {String.t(), String.t() | nil}
  def key(spreadsheet_id, opts \\ []) do
    {spreadsheet_id, Keyword.get(opts, :list_name)}
  end
end
