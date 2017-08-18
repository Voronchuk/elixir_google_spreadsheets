defmodule GSS.Mixfile do
    use Mix.Project

    def project do
        [
            app: :elixir_google_spreadsheets,
            version: "0.1.7",
            elixir: "~> 1.4",
            description: "Elixir library to read and write data of Google Spreadsheets.",
            docs: [extras: ["README.md"]],
            build_embedded: Mix.env == :prod,
            start_permanent: Mix.env == :prod,
            package: package(),
            elixirc_paths: elixirc_paths(Mix.env),
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
                :gen_stage,
                :poison
            ],
            mod: {GSS, []}
        ]
    end

    defp deps do
        [
            {:goth, "~> 0.5.0"},
            {:httpoison, "~> 0.12"},
            {:gen_stage, ">= 0.12.0"},
            {:poison, "~> 3.1"},
            {:earmark, ">= 0.0.0", only: :dev},
            {:ex_doc, ">= 0.0.0", only: :dev},
            {:logger_file_backend, ">= 0.0.10", only: [:dev, :test]},
            #{:json_web_token, git: "https://github.com/starbuildr/json_web_token_ex.git", override: true},
            {:dialyxir, "~> 0.5", only: :dev, runtime: false}
        ]
    end

    defp elixirc_paths(:test), do: ["lib", "test/stub_modules"]
    defp elixirc_paths(_), do: ["lib"]
end
