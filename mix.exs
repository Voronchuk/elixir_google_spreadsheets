defmodule GSS.Mixfile do
  use Mix.Project

  def project do
    [
      app: :elixir_google_spreadsheets,
      version: "0.4.0",
      elixir: "~> 1.17",
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
        :gen_stage
      ],
      mod: {GSS, []}
    ]
  end

  defp deps do
    [
      {:goth, "~> 1.4"},
      {:gen_stage, "~> 1.2"},
      {:finch, "~> 0.19"},
      {:jason, "~> 1.4"},
      {:earmark, ">= 0.0.0", only: :dev},
      {:ex_doc, "~> 0.37", only: :dev, runtime: false},
      {:logger_file_backend, ">= 0.0.12", only: [:dev, :test]},
      {:dialyxir, "~> 1.1", only: :dev, runtime: false}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/stub_modules"]
  defp elixirc_paths(_), do: ["lib"]
end
