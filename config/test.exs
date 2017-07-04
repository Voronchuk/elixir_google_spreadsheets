use Mix.Config

config :elixir_google_spreadsheets,
  spreadsheet_id: "1h85keViqbRzgTN245gEw5s9roxpaUtT7i-mNXQtT8qQ"

config :elixir_google_spreadsheets, :client,
  request_workers: 30,
  max_demand: 100,
  max_interval: :timer.seconds(100),
  interval: 100

if File.exists?("config/test.local.exs") do
  import_config "test.local.exs"
end
