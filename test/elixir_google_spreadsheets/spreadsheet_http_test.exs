defmodule GSS.SpreadsheetHttpTest do
  @moduledoc """
  Exercises the full `GSS.Spreadsheet -> GSS.Client -> Limiter -> Request -> Finch`
  pipeline against a localhost stub HTTP server (real Finch, localhost only).

  `async: false` because every test mutates the global `:api_url` application config
  (and the stale-key test also mutates `:client`). The `Authorization: Bearer test-token`
  header comes from the `GSS.TestToken` stub wired in `config/test.exs`, so a passing
  request proves the whole auth path end to end.

  A `GSS.StubModules.HttpServer` (a bare `Plug.Cowboy` server) stands in for Bypass here:
  Bypass routes through `Plug.Router`, which raises `Plug.Router.InvalidSpecError` on the
  literal colon in Sheets ranges like `A1:E1`. See that module's docs for the full
  rationale — production URLs must keep those literal colons for Google's custom methods.
  """
  use ExUnit.Case, async: false

  import Plug.Conn

  alias GSS.Spreadsheet
  alias GSS.StubModules.HttpServer

  @row ["1", "2", "3", "4", "5"]

  setup context do
    {:ok, dispatcher} =
      Agent.start_link(fn ->
        fn conn -> resp(conn, 500, "no stub handler configured") end
      end)

    {port, ref} = HttpServer.start(fn conn -> Agent.get(dispatcher, & &1).(conn) end)

    previous_api_url = Application.get_env(:elixir_google_spreadsheets, :api_url)

    Application.put_env(
      :elixir_google_spreadsheets,
      :api_url,
      "http://localhost:#{port}/v4/spreadsheets/"
    )

    # Registry dedups by spreadsheet id, so a per-test id keeps processes isolated.
    id = "sheet-" <> (context.test |> to_string() |> String.replace(~r/[^A-Za-z0-9]/, "-"))
    {:ok, pid} = Spreadsheet.Supervisor.spreadsheet(id)

    on_exit(fn ->
      if Process.alive?(pid) do
        DynamicSupervisor.terminate_child(Spreadsheet.Supervisor, pid)
      end

      if previous_api_url do
        Application.put_env(:elixir_google_spreadsheets, :api_url, previous_api_url)
      else
        Application.delete_env(:elixir_google_spreadsheets, :api_url)
      end

      HttpServer.stop(ref)
      if Process.alive?(dispatcher), do: Agent.stop(dispatcher)
    end)

    {:ok, dispatcher: dispatcher, pid: pid, id: id}
  end

  describe "read_row/3" do
    test "happy path returns the values and forwards the bearer token", %{
      dispatcher: dispatcher,
      pid: pid,
      id: id
    } do
      test_pid = self()

      stub(dispatcher, fn conn ->
        send(
          test_pid,
          {:req, conn.method, conn.request_path, get_req_header(conn, "authorization")}
        )

        json_resp(conn, 200, %{"values" => [@row]})
      end)

      assert {:ok, @row} = Spreadsheet.read_row(pid, 1, column_from: 1, column_to: 5)

      assert_receive {:req, "GET", path, ["Bearer test-token"]}
      assert path == "/v4/spreadsheets/#{id}/values/A1:E1"
    end
  end

  describe "write_row/4" do
    test "happy path returns :ok and PUTs a JSON body carrying the right range", %{
      dispatcher: dispatcher,
      pid: pid,
      id: id
    } do
      test_pid = self()

      stub(dispatcher, fn conn ->
        send(
          test_pid,
          {:req, conn.method, conn.request_path, JSON.decode!(conn.private.raw_body)}
        )

        json_resp(conn, 200, %{"updatedRows" => 1, "updatedColumns" => 5})
      end)

      assert :ok = Spreadsheet.write_row(pid, 1, @row)

      assert_receive {:req, "PUT", path, decoded}
      assert path == "/v4/spreadsheets/#{id}/values/A1:E1"
      assert decoded["range"] == "A1:E1"
      assert decoded["values"] == [@row]
    end
  end

  describe "error handling" do
    test "a non-200 status becomes {:error, %GSS.GoogleApiError{}}", %{
      dispatcher: dispatcher,
      pid: pid
    } do
      stub(dispatcher, fn conn ->
        json_resp(conn, 403, %{
          "error" => %{"code" => 403, "status" => "PERMISSION_DENIED", "message" => "forbidden"}
        })
      end)

      assert {:error, %GSS.GoogleApiError{}} =
               Spreadsheet.read_row(pid, 1, column_from: 1, column_to: 5)
    end
  end

  describe "retry on 429" do
    test "retries a 429 and returns the eventual 200 body (exactly 2 requests)", %{
      dispatcher: dispatcher,
      pid: pid
    } do
      {:ok, counter} = Agent.start_link(fn -> 0 end)
      on_exit(fn -> if Process.alive?(counter), do: Agent.stop(counter) end)

      stub(dispatcher, fn conn ->
        attempt = Agent.get_and_update(counter, fn n -> {n, n + 1} end)

        if attempt == 0 do
          json_resp(conn, 429, %{
            "error" => %{
              "code" => 429,
              "status" => "RESOURCE_EXHAUSTED",
              "message" => "slow down"
            }
          })
        else
          json_resp(conn, 200, %{"values" => [@row]})
        end
      end)

      # attempt-0 backoff is 1001..2000ms, so bump the outer call timeout well past it.
      assert {:ok, @row} =
               Spreadsheet.read_row(pid, 1, column_from: 1, column_to: 5, timeout: 30_000)

      assert Agent.get(counter, & &1) == 2
    end
  end

  describe "stale request_opts keys" do
    test "HTTPoison-era :timeout/:recv_timeout keys are stripped before reaching Finch", %{
      dispatcher: dispatcher,
      pid: pid
    } do
      previous_client = Application.get_env(:elixir_google_spreadsheets, :client, [])

      Application.put_env(
        :elixir_google_spreadsheets,
        :client,
        Keyword.put(previous_client, :request_opts, timeout: 5_000, recv_timeout: 5_000)
      )

      on_exit(fn ->
        Application.put_env(:elixir_google_spreadsheets, :client, previous_client)
      end)

      stub(dispatcher, fn conn -> json_resp(conn, 200, %{"values" => [@row]}) end)

      # finch 0.23 raises ArgumentError on unknown keys like :timeout/:recv_timeout, so a
      # successful read proves the request-worker whitelist stripped them before Finch.
      assert {:ok, @row} = Spreadsheet.read_row(pid, 1, column_from: 1, column_to: 5)
    end
  end

  describe "missing auth config" do
    test "returns {:error, %GSS.MissingAuthConfig{}} without crashing the process", %{pid: pid} do
      # Snapshot all auth config keys (precedence: token_generator → goth → source → json)
      auth_keys = [:token_generator, :goth, :source, :json]

      previous_auth =
        Enum.map(auth_keys, fn key ->
          {key, Application.fetch_env(:elixir_google_spreadsheets, key)}
        end)

      # Delete all auth config keys to force MissingAuthConfig
      Enum.each(auth_keys, fn key ->
        Application.delete_env(:elixir_google_spreadsheets, key)
      end)

      on_exit(fn ->
        # Restore exactly as it was: put_env if it was present, delete_env if it was absent
        Enum.each(previous_auth, fn {key, result} ->
          case result do
            {:ok, value} ->
              Application.put_env(:elixir_google_spreadsheets, key, value)

            :error ->
              Application.delete_env(:elixir_google_spreadsheets, key)
          end
        end)
      end)

      # Ensure all auth sources are cleared so GSS.Auth.token!/0 raises GSS.MissingAuthConfig;
      # the query helper must turn that into an ordinary error tuple rather than crash the GenServer.
      assert {:error, %GSS.MissingAuthConfig{}} =
               Spreadsheet.read_row(pid, 1, column_from: 1, column_to: 5)

      assert Process.alive?(pid)
    end
  end

  # Install the handler the stub server dispatches the next request to.
  @spec stub(pid(), (Plug.Conn.t() -> Plug.Conn.t())) :: :ok
  defp stub(dispatcher, handler) when is_function(handler, 1) do
    Agent.update(dispatcher, fn _ -> handler end)
  end

  @spec json_resp(Plug.Conn.t(), non_neg_integer(), map()) :: Plug.Conn.t()
  defp json_resp(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> resp(status, JSON.encode!(body))
  end
end
