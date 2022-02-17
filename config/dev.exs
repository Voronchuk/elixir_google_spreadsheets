import Config

config :elixir_google_spreadsheets, :client,
  request_workers: 50,
  max_demand: 100,
  max_interval: :timer.minutes(1),
  interval: 100

if File.exists?("config/dev.local.exs") do
  import_config "dev.local.exs"
end
