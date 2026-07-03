import Config

# Keyless offline boot: `:token_generator` is resolved first by `GSS.Auth`, so the
# application starts with no Goth child and no service-account key file. Every request
# then carries `Authorization: Bearer test-token`. Live integration runs override this
# in `config/test.local.exs` (set `token_generator: nil` plus real `json:`/`source:`).
config :elixir_google_spreadsheets,
  spreadsheet_id:
    System.get_env("GSS_TEST_SPREADSHEET_ID", "1h85keViqbRzgTN245gEw5s9roxpaUtT7i-mNXQtT8qQ"),
  token_generator: {GSS.TestToken, :fetch, []}

config :elixir_google_spreadsheets, :client, request_workers: 30

config :logger, level: :info

if File.exists?("config/test.local.exs") do
  import_config "test.local.exs"
end
