defmodule GSS do
  @moduledoc """
  Bootstrap Google Spreadsheet application.
  """

  use Application

  def start(_type, _args) do
    # TODO Accept also from System.fetch_env.
    # https://github.com/peburrows/goth#installation
    credentials = Application.fetch_env!(:elixir_google_spreadsheets, :json)
    |> Jason.decode!()
    scopes = ["https://www.googleapis.com/auth/spreadsheets"]
    source = {:service_account, credentials, scopes: scopes}

    children = [
      {Goth, name: GSS.Goth, source: source},
      {GSS.Registry, []},
      {GSS.Spreadsheet.Supervisor, []},
      {GSS.Client.Supervisor, []}
    ]

    Supervisor.start_link(children, strategy: :one_for_all)
  end

  @doc """
  Read config settings scoped for GSS.
  """
  @spec config(atom(), any()) :: any()
  def config(key, default \\ nil) do
    Application.get_env(:elixir_google_spreadsheets, key, default)
  end
end
