use Mix.Config

# TODO: add config use genstage or not

config :logger,
  backends: [:console, {LoggerFileBackend, :file_log}],
  handle_otp_reports: true,
  handle_sasl_reports: true

config :logger, :file_log,
  level: :debug,
  path: "log/#{Mix.env}.log"

config :logger, :console,
  level: :error

config :elixir_google_spreadsheets, :client,
  request_workers: 2,
  max_demand: 2,
  max_interval: 7_000,
  interval: 700

if File.exists?("config/dev.local.exs") do
  import_config "dev.local.exs"
end
