defmodule GSS.Mixfile do
    use Mix.Project

    def project do
        [
            app: :elixir_google_spreadsheets,
            version: "0.1.0",
            elixir: "~> 1.3",
            build_embedded: Mix.env == :prod,
            start_permanent: Mix.env == :prod,
            deps: deps()
        ]
    end


    def application do
        [
            applications: [
                :logger,
                :goth,
                :httpoison,
            ]
        ]
    end


    defp deps do
        [
            {:goth, "~> 0.2.1"},
            {:hackney, "1.6.1"},
            {:httpoison, "~> 0.9.2"}
        ]
    end
end
