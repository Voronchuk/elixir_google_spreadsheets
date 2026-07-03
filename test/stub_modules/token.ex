defmodule GSS.TestToken do
  @moduledoc """
  Stub auth token generator used by the offline test suite.

  Wired via `config :elixir_google_spreadsheets, token_generator: {GSS.TestToken, :fetch, []}`
  in `config/test.exs`. Because `GSS.Auth` resolves `:token_generator` first, the
  application boots with NO Goth child and NO service-account key file, and every
  request carries `Authorization: Bearer test-token`.
  """

  @spec fetch() :: {:ok, String.t()}
  def fetch, do: {:ok, "test-token"}
end
