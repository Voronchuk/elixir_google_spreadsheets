import Config

config :elixir_google_spreadsheets, :client, request_workers: 50

if File.exists?("config/dev.local.exs") do
  import_config "dev.local.exs"
end
