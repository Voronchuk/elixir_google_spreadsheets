defmodule GSS do
  @moduledoc """
  Bootstrap Google Spreadsheet application.
  """

  use Application

  require Logger

  alias GSS.Auth

  def start(_type, _args) do
    children =
      [
        {GSS.Registry, []},
        {Finch, name: GSS.Finch},
        {GSS.Spreadsheet.Supervisor, []},
        {GSS.Client.Supervisor, []}
      ] ++ List.wrap(Auth.goth_child_spec())

    unless Auth.configured?() do
      Logger.warning(
        "GSS: no authentication configured — booted without a Goth child and will raise " <>
          "GSS.MissingAuthConfig on the first API request. Configure one of :token_generator, " <>
          ":goth, :source or :json for :elixir_google_spreadsheets."
      )
    end

    Supervisor.start_link(children, strategy: :one_for_all, name: GSS.Supervisor)
  end

  @doc """
  Read config settings scoped for GSS.
  """
  @spec config(atom(), any()) :: any()
  def config(key, default \\ nil) do
    Application.get_env(:elixir_google_spreadsheets, key, default)
  end
end
