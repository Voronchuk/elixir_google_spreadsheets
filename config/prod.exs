use Mix.Config

config :elixir_google_spreadsheets, :client,
  request_workers: 100,
  max_demand: 100,
  max_interval: :timer.seconds(60),
  interval: 100
