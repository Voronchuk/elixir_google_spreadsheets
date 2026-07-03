defmodule GSS.GoogleApiError do
  @moduledoc """
  Raised in case non 200 response code from Google Cloud API.
  """
  defexception [:message]
end

defmodule GSS.InvalidColumnIndex do
  @moduledoc """
  Raised in case more than 255 columns is queried.
  """
  defexception [:message]
end

defmodule GSS.InvalidRange do
  @moduledoc """
  Raised in case invalid range is defined.
  """
  defexception [:message]
end

defmodule GSS.InvalidInput do
  @moduledoc """
  Raised in case invalid input params are passed
  """
  defexception [:message]
end

defmodule GSS.MissingAuthConfig do
  @moduledoc """
  Raised on the first API request when no authentication is configured for
  `:elixir_google_spreadsheets`.
  """
  defexception message: """
               no authentication configured for :elixir_google_spreadsheets. Set one of (first configured wins):

                   # escape hatch / tests: an MFA returning {:ok, token}
                   config :elixir_google_spreadsheets, token_generator: {MyApp, :fetch_token, []}

                   # reuse a Goth instance already running in your app
                   config :elixir_google_spreadsheets, goth: MyApp.Goth

                   # any Goth source; GSS starts its own Goth
                   config :elixir_google_spreadsheets, source: {:metadata, []}

                   # legacy: raw service-account JSON; GSS starts its own Goth
                   config :elixir_google_spreadsheets, json: File.read!("service_account.json")
               """
end
