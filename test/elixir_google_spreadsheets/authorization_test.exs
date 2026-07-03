defmodule GSS.AuthorizationTest do
  use ExUnit.Case, async: true

  # Live auth test — excluded by default; run with `mix test --include integration`.
  #
  # Under the default offline config, `GSS.Auth.token!/0` resolves the
  # `:token_generator` stub (`GSS.TestToken`) and would return "test-token", which
  # does NOT prove real authentication. To exercise the real auth path, provide a
  # `config/test.local.exs` that unsets the stub and configures real credentials:
  #
  #     import Config
  #     config :elixir_google_spreadsheets,
  #       token_generator: nil,
  #       json: File.read!("config/service_account.json")
  #
  # (`nil` counts as unset per the `GSS.Auth` precedence rules, so the next
  # configured source — `:json`/`:source`/`:goth` — takes over.)
  @moduletag :integration

  test "fetch account access token to work with Google Spreadsheets" do
    assert is_binary(GSS.Auth.token!())
  end
end
