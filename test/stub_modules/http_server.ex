defmodule GSS.StubModules.HttpServer do
  @moduledoc """
  Minimal `Plug.Cowboy` stub server used by `GSS.SpreadsheetHttpTest` to exercise the
  full request pipeline (`GSS.Spreadsheet -> Client -> Limiter -> Request -> Finch`)
  against localhost.

  Bypass cannot be used here. Bypass routes every request through `Plug.Router`, whose
  path compiler (`Plug.Router.Utils.build_path_match/1` under plug 1.20) raises
  `Plug.Router.InvalidSpecError` on the literal colon in Google Sheets ranges such as
  `A1:E1`. Those literal colons are non-negotiable in production — Google's custom
  methods (`values:batchGet`, `:append`, `:clear`, `:batchUpdate`) are matched on the
  literal `:` — so the URLs the client builds cannot be percent-encoded to appease the
  router. This plug instead reads `conn.request_path` directly (no router, no path
  compilation), so colon paths pass straight through.

  Start a server with a dispatcher `(Plug.Conn.t -> Plug.Conn.t)` closure; the request
  body is pre-read into `conn.private[:raw_body]` so handlers can decode it without
  touching the body stream again.
  """

  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(dispatcher) when is_function(dispatcher, 1), do: dispatcher

  @impl true
  def call(conn, dispatcher) do
    {:ok, body, conn} = read_body(conn)

    conn
    |> put_private(:raw_body, body)
    |> dispatcher.()
  end

  @doc """
  Start a stub server on an ephemeral port. Returns `{port, ref}`; pass `ref` to
  `stop/1` for teardown.
  """
  @spec start((Plug.Conn.t() -> Plug.Conn.t())) :: {non_neg_integer(), reference()}
  def start(dispatcher) when is_function(dispatcher, 1) do
    ref = make_ref()
    {:ok, _pid} = Plug.Cowboy.http(__MODULE__, dispatcher, ref: ref, port: 0)
    {:ranch.get_port(ref), ref}
  end

  @doc """
  Shut down a stub server started with `start/1`.
  """
  @spec stop(reference()) :: :ok
  def stop(ref), do: Plug.Cowboy.shutdown(ref)
end
