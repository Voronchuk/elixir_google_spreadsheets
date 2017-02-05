defmodule GSS.Mixfile do
    use Mix.Project

    def project do
        [
            app: :elixir_google_spreadsheets,
            version: "0.1.1",
            elixir: "~> 1.3",
            description: "Elixir library to read and write data of Google Spreadsheets.",
            docs: [extras: ["README.md"]],
            build_embedded: Mix.env == :prod,
            start_permanent: Mix.env == :prod,
            package: package,
            deps: deps()
        ]
    end

    def package do
        [ 
            name: :elixir_google_spreadsheets,
            files: ["lib", "mix.exs"],
            maintainers: ["Vyacheslav Voronchuk"],
            licenses: ["MIT"],
            links: %{"Github" => "https://github.com/Voronchuk/elixir_google_spreadsheets"},
        ]
    end

    def application do
        [
            applications: [
                :logger,
                :goth,
                :httpoison,
            ],
            mod: {GSS, []}
        ]
    end

    defp deps do
        [
            {:goth, "~> 0.2.1"},
            {:hackney, "1.6.1"},
            {:httpoison, "~> 0.9.2"},
            {:earmark, ">= 0.0.0", only: :dev},
            {:ex_doc, ">= 0.0.0", only: :dev},
        ]
    end
end
