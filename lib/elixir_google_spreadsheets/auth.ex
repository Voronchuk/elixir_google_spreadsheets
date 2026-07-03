defmodule GSS.Auth do
  @moduledoc """
  Authentication for the Google Sheets API.

  A bearer token is resolved at request time from the first configured source,
  in this order of precedence (first configured wins):

    * `:token_generator` — `{module, function, args}` returning `{:ok, token}`;
      an escape hatch, also used to stub auth in tests.
    * `:goth` — the name of a `Goth` instance already running in the host
      application. GSS starts no Goth child of its own.
    * `:source` — any `Goth` source (e.g. `:default`, `{:metadata, []}`,
      `{:service_account, credentials, opts}`). GSS starts its own Goth child.
    * `:json` — legacy raw service-account JSON string, turned into a
      `{:service_account, ...}` source. GSS starts its own Goth child.

  "Configured" means `Application.get_env/2` returns a non-nil value; an
  explicitly-set `nil` counts as unset (the escape hatch for `*.local.exs`
  overrides). When nothing is configured, `token!/0` raises
  `GSS.MissingAuthConfig`.
  """

  alias GSS.MissingAuthConfig

  @type mfargs :: {module(), atom(), list()}

  @default_scopes ["https://www.googleapis.com/auth/spreadsheets"]

  @doc """
  Return the bearer token string for the Google Sheets API.

  Raises `GSS.MissingAuthConfig` when no authentication is configured.
  """
  @spec token!() :: String.t()
  def token! do
    case resolve() do
      {:token_generator, {mod, fun, args}} ->
        {:ok, token} = apply(mod, fun, args)
        token

      {:goth, name} ->
        Goth.fetch!(name).token

      {:own_goth, _source} ->
        Goth.fetch!(GSS.Goth).token

      :none ->
        raise MissingAuthConfig
    end
  end

  @doc """
  Whether any authentication source is configured.
  """
  @spec configured?() :: boolean()
  def configured? do
    resolve() != :none
  end

  @doc """
  Child spec for GSS's own `Goth` instance, or `nil` when GSS must not start
  one (host app supplies its own `Goth`, uses a token generator, or nothing is
  configured).
  """
  @spec goth_child_spec() :: {module(), keyword()} | nil
  def goth_child_spec do
    case resolve() do
      {:own_goth, source} ->
        {Goth, name: GSS.Goth, source: source, http_client: {&__MODULE__.finch_http_client/1, []}}

      _ ->
        nil
    end
  end

  @doc false
  # Goth `http_client` callback that reuses the shared `GSS.Finch` pool instead
  # of spinning up Goth's own. Contract (per Goth.Token.fetch/1): a 1-arity
  # function receiving `[method:, url:, headers:, body:]` (plus any opts) and
  # returning `{:ok, %{status:, headers:, body:}}` or `{:error, exception}` —
  # exactly what `Finch.request/3` yields.
  @spec finch_http_client(keyword()) :: {:ok, map()} | {:error, Exception.t()}
  def finch_http_client(options) do
    {method, options} = Keyword.pop!(options, :method)
    {url, options} = Keyword.pop!(options, :url)
    {headers, options} = Keyword.pop!(options, :headers)
    {body, options} = Keyword.pop!(options, :body)

    method
    |> Finch.build(url, headers, body)
    |> Finch.request(GSS.Finch, options)
  end

  # Resolve the active auth strategy following the documented precedence.
  @spec resolve() ::
          {:token_generator, mfargs()}
          | {:goth, module()}
          | {:own_goth, term()}
          | :none
  defp resolve do
    cond do
      mfa = GSS.config(:token_generator) -> {:token_generator, mfa}
      goth = GSS.config(:goth) -> {:goth, goth}
      source = GSS.config(:source) -> {:own_goth, source}
      json = GSS.config(:json) -> {:own_goth, json_source(json)}
      true -> :none
    end
  end

  @spec json_source(String.t()) :: {:service_account, map(), keyword()}
  defp json_source(json) do
    scopes = GSS.config(:scopes) || @default_scopes
    {:service_account, JSON.decode!(json), scopes: scopes}
  end
end
