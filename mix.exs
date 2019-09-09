defmodule GSS.Mixfile do
  use Mix.Project

  def project do
    [
      app: :elixir_google_spreadsheets,
      version: "0.1.15",
      elixir: "~> 1.6",
      description: "Elixir library to read and write data of Google Spreadsheets.",
      docs: [extras: ["README.md"]],
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      package: package(),
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps()
    ]
  end

  def package do
    [
      name: :elixir_google_spreadsheets,
      files: ["lib", "mix.exs"],
      maintainers: ["Vyacheslav Voronchuk"],
      licenses: ["MIT"],
      links: %{"Github" => "https://github.com/Voronchuk/elixir_google_spreadsheets"}
    ]
  end

  def application do
    [
      applications: [
        :logger,
        :goth,
        :httpoison,
        :gen_stage,
        :poison
      ],
      mod: {GSS, []}
    ]
  end

  defp deps do
    [
      {:goth, "~> 1.0"},
      {:httpoison, "~> 1.4"},
      {:gen_stage, "~> 0.14"},
      {:poison, "~> 3.1"},
      {:earmark, ">= 0.0.0", only: :dev},
      {:ex_doc, "~> 0.19", only: :dev},
      {:logger_file_backend, ">= 0.0.10", only: [:dev, :test]},
      {:dialyxir, "~> 0.5", only: :dev, runtime: false}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/stub_modules"]
  defp elixirc_paths(_), do: ["lib"]
end
