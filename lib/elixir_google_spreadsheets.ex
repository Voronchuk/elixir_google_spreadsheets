defmodule GSS do
  @moduledoc """
  Bootstrap Google Spreadsheet application.
  """

  use Application

  def start(_type, _args) do
    GSS.Supervisor.init([])
  end

  @doc """
  Read config settings scoped for GSS.
  """
  @spec config(atom(), any()) :: any()
  def config(key, default \\ nil) do
    Application.get_env(:elixir_google_spreadsheets, key, default)
  end
end
