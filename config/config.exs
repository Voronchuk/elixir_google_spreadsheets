# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
import Config

# This configuration is loaded before any dependency and is restricted
# to this project. If another project depends on this project, this
# file won't be loaded nor affect the parent project. For this reason,
# if you want to provide default values for your application for
# 3rd-party users, it should be done in your "mix.exs" file.

# You can configure for your application as:
#
#     config :mongo_ecto, key: :value
#
# And access this configuration in your application as:
#
#     Application.get_env(:mongo_ecto, :key)
#
# Or configure a 3rd-party app:
#
#     config :logger, level: :info
#
#
# It is also possible to import configuration files, relative to this
# directory. For example, you can emulate configuration per environment
# by uncommenting the line below and defining dev.exs, test.exs and such.
# Configuration from the imported file will override the ones defined
# here (which is why it is important to import them last).
#
config :goth,
  json: "./config/service_account.json" |> File.read!()

config :elixir_google_spreadsheets,
  max_rows_per_request: 301,
  default_column_from: 1,
  default_column_to: 26

config :elixir_google_spreadsheets, :client,
  request_workers: 50,
  max_demand: 100,
  max_interval: :timer.minutes(1),
  interval: 100,
  result_timeout: :timer.minutes(10),
  request_opts: [
    timeout: :timer.seconds(8),
    recv_timeout: :timer.seconds(5)
  ]

import_config "#{Mix.env()}.exs"
