defmodule GSS.Mixfile do
  use Mix.Project

  def project do
    [
      app: :elixir_google_spreadsheets,
      version: "1.0.0",
      elixir: "~> 1.18",
      description: "Elixir library to read and write data of Google Spreadsheets.",
      docs: [main: "GSS", extras: ["README.md"]],
      start_permanent: Mix.env() == :prod,
      package: package(),
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      dialyzer: [plt_file: {:no_warn, "priv/plts/project.plt"}]
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
      extra_applications: [:logger],
      mod: {GSS, []}
    ]
  end

  defp deps do
    [
      {:goth, "~> 1.4"},
      {:gen_stage, "~> 1.3"},
      {:finch, "~> 0.23"},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:plug_cowboy, "~> 2.7", only: :test}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/stub_modules"]
  defp elixirc_paths(_), do: ["lib"]
end
