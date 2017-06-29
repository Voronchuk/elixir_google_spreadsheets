use Mix.Config

# TODO: add config use genstage or not
# TODO:

config :logger,
  backends: [:console, {LoggerFileBackend, :file_log}]

config :logger, :file_log,
  level: :debug,
  path: "log/#{Mix.env}.log"

config :logger, :console,
  level: :error
