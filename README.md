# Elixir Google Spreadsheets
Elixir library to read and write data of Google Spreadsheets.

This library is based on __Google Cloud API v4__ and uses __Google Service Accounts__ to manage it's content.

## Integration with Ecto
Check [ecto_gss](https://github.com/Voronchuk/ecto_gss) if you need to integrate your Google Spreadsheet with Ecto changesets for validation and other features.

# Setup
1. Use [this](https://console.developers.google.com/start/api?id=sheets.googleapis.com) wizard to create or select a project in the Google Developers Console and automatically turn on the API. Click __Continue__, then __Go to credentials__.
2. On the __Add credentials to your project page__, create __Service account key__.
3. Select your project name as service account and __JSON__ as key format, download the created key and rename it to __service_account.json__.
4. Press __Manage service accounts__ on a credential page, copy your __Service Account Identifier__: _[projectname]@[domain].iam.gserviceaccount.com_
5. Create or open existing __Google Spreadsheet document__ on your __Google Drive__ and add __Service Account Identifier__ as user invited in spreadsheet's __Collaboration Settings__.
6. Add `{:elixir_google_spreadsheets, "~> 1.0"}` to __mix.exs__ under `deps` function.
7. Point the library at __service_account.json__. Load the key at runtime in `config/runtime.exs` so the private key is not baked into your compiled release:

    ```elixir
    # config/runtime.exs
    config :elixir_google_spreadsheets,
      json: File.read!("./config/service_account.json")
    ```

    See [Authentication options](#authentication-options) below for alternatives.
8. Run `mix deps.get && mix deps.compile`.

## Authentication options
A bearer token is resolved at request time from the first configured source, in this order of precedence (first configured wins):

```elixir
config :elixir_google_spreadsheets,
  # 1. Escape hatch / tests: an MFA returning {:ok, token}
  token_generator: {MyApp, :fetch_token, []},

  # 2. Reuse a Goth instance already running in your app (GSS starts no Goth child)
  goth: MyApp.Goth,

  # 3. Any Goth source; GSS starts its own Goth child
  source: {:metadata, []}, # or :default, {:service_account, credentials, opts}, ...

  # 4. Legacy: raw service-account JSON string; GSS starts its own Goth child
  json: File.read!("./config/service_account.json"),

  # Scopes for the :json path (default below)
  scopes: ["https://www.googleapis.com/auth/spreadsheets"]
```

If none of these is configured, the library still boots (logging a warning) and raises `GSS.MissingAuthConfig` on the first API request.

## Testing
`mix test` runs the full suite offline against a local stub HTTP server — no credentials
and no network access required. Tests that hit the real Google Sheets API are tagged
`:integration` and excluded by default; run them with real credentials via:

```sh
mix test --include integration
```

This needs a `config/test.local.exs` with real authentication configured (set
`token_generator: nil` and either `json:` or `source:`, see [Authentication
options](#authentication-options) above). The [testing
spreadsheet](https://docs.google.com/spreadsheets/d/1h85keViqbRzgTN245gEw5s9roxpaUtT7i-mNXQtT8qQ/edit?usp=sharing)
is used by default and can be copied into your own Drive; point the suite at your copy
with the `GSS_TEST_SPREADSHEET_ID` environment variable.

## API limits
Google's Sheets API quotas are 60 read + 60 write requests/min/user (two separate
buckets), and Google has announced billing for quota overages later in 2026, so
staying under these limits matters. The suggested quota-aligned params are:

```elixir
config :elixir_google_spreadsheets, :client,
  request_workers: 50,
  max_demand: 60,
  max_interval: :timer.minutes(1),
  interval: 100,
  result_timeout: :timer.minutes(10),
  max_retries: 3,
  request_opts: [] # See Finch request options
```

`max_demand` is applied per partition, so read and write each get their own 60/min
budget, matching Google's two buckets.

`request_opts` (and the per-call `options` argument accepted by `GSS.Client.request/5`)
only forward `:pool_timeout`, `:receive_timeout` and `:request_timeout` on to
`Finch.request/3`; any other keys are ignored.

### Retries
Requests that fail transiently are retried automatically and re-enter the same
rate-limited pipeline:

* HTTP `429` (rate limited) is retried for **all** methods — the request was
  rejected, not executed.
* HTTP `500/502/503/504` and transport errors are retried for **`:get` only**,
  because writes are not idempotent and a 5xx write may already have been applied
  server-side.

Backoff is exponential with jitter: `min(2^attempt seconds, 32s) + rand(1..1000ms)`.
A `Retry-After` response header (integer seconds) is honoured as a floor. The number
of retries is controlled by `max_retries` (default `3`; set to `0` to disable). Note
that a short custom `result_timeout` can make the caller's `GenStage.call/3` time out
while a retry is still in flight; the default `result_timeout` of `:timer.minutes(10)`
is sized to cover the worst case (`max_retries` exhausted with full backoff).

### Observability
Finch emits its own [`:telemetry`](https://hexdocs.pm/telemetry) events for every HTTP
request (`[:finch, :request, :start | :stop | :exception]`, plus pool/connect/send/recv
events) — attach a handler to these for latency and error instrumentation without
modifying this library.

# Usage
Initialise spreadsheet thread with it's id which you can fetch from URL:

```elixir
    {:ok, pid} = GSS.Spreadsheet.Supervisor.spreadsheet("XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX-XXXXXXXXX")
```

Or if you wish to edit only a specific list:

```elixir
    {:ok, pid} = GSS.Spreadsheet.Supervisor.spreadsheet(
        "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX-XXXXXXXXX",
        list_name: "my_list3"
    )
```

Sample operations:

* `GSS.Spreadsheet.id(pid)`
* `GSS.Spreadsheet.properties(pid)`
* `GSS.Spreadsheet.get_sheet_id(pid)`
* `GSS.Spreadsheet.sheets(pid)`
* `GSS.Spreadsheet.rows(pid)`
* `GSS.Spreadsheet.update_sheet_size(pid, 10, 5)`
* `GSS.Spreadsheet.read_row(pid, 1, column_to: 5)`
* `GSS.Spreadsheet.read_rows(pid, 1, 10, column_to: 5, pad_empty: true)`
* `GSS.Spreadsheet.read_rows(pid, [1, 3, 5], column_to: 5, pad_empty: true)`
* `GSS.Spreadsheet.read_rows(pid, ["A1:E1", "A2:E2"])`
* `GSS.Spreadsheet.write_row(pid, 1, ["1", "2", "3", "4", "5"])`
* `GSS.Spreadsheet.write_rows(pid, ["A2:E2", "A3:F3"], [["1", "2", "3", "4", "5"], ["1", "2", "3", "4", "5", "6"]])`
* `GSS.Spreadsheet.append_row(pid, 1, ["1", "2", "3", "4", "5"])`
* `GSS.Spreadsheet.append_rows(pid, 1, [["1", "2", "3", "4", "5"], ["1", "2", "3", "4", "5", "6"]])`
* `GSS.Spreadsheet.clear_row(pid, 1)`
* `GSS.Spreadsheet.clear_rows(pid, 1, 10)`
* `GSS.Spreadsheet.clear_rows(pid, ["A1:E1", "A2:E2"])`
* `GSS.Spreadsheet.set_basic_filter(pid, %{row_from: 0, row_to: 5, col_from: 1, col_to: 10}, %{col_idx: 2, condition_type: "TEXT_CONTAINS", user_entered_value: "test"})`
* `GSS.Spreadsheet.set_basic_filter(pid, %{row_from: nil, row_to: nil, col_from: nil, col_to: nil}, %{})`
* `GSS.Spreadsheet.clear_basic_filter(pid)`
* `GSS.Spreadsheet.freeze_header(pid, %{dim: :row, n_freeze: 1})`
* `GSS.Spreadsheet.freeze_header(pid, %{dim: :col, n_freeze: 2})`
* `GSS.Spreadsheet.update_col_width(pid, %{col_idx: 1, col_width: 200})`
* `GSS.Spreadsheet.add_number_format(pid, %{row_from: 0, row_to: nil, col_from: 3, col_to: 4}, %{type: "NUMBER", pattern: "#0.0%"})`
* `GSS.Spreadsheet.update_col_wrap(pid, %{row_from: 0, row_to: nil, col_from: 5, col_to: 7}, %{wrap_strategy: "clip"})`
* `GSS.Spreadsheet.set_font(pid, %{row_from: nil, row_to: nil, col_from: nil, col_to: nil}, %{font_family: "Source Code Pro"})`
* `GSS.Spreadsheet.add_conditional_format(pid, %{row_from: nil, row_to: nil, col_from: nil, col_to: nil}, %{formula: "=$E1=\"TEST\"", color_map: %{red: 1, green: 0.8, blue: 0.8}})`
* `GSS.Spreadsheet.update_border(pid, %{row_from: 0, row_to: 10, col_from: 2, col_to: 5}, %{top: %{red: 1, style: "dashed"}, bottom: %{green: 1, blue: 0.7}, left: %{blue: 0.8, alpha: 0.75}})`

Last function param of `GSS.Spreadsheet` function calls support the same `Keyword` options (in snake_case instead of camelCase), as defined in [Google API Docs](https://developers.google.com/sheets/reference/rest/v4/spreadsheets.values).

We also define `column_from` and `column_to` Keyword options which control range of cell which will be queried.

Default values:
* `column_from = 1` - default is configurable as `:default_column_from`
* `column_to = 26` - default is configurable as `:default_column_to`
* `major_dimension = "ROWS"`
* `value_render_option = "FORMATTED_VALUE"`
* `datetime_render_option = "FORMATTED_STRING"`
* `value_render_option = "USER_ENTERED"`
* `insert_data_option = "INSERT_ROWS"`

# Suggestions
* Recommended columns __26__ (more on your own risk), max rows in a batch __100-300__ depending on your data size per row, configurable as `:max_rows_per_request`;
* __Pull requests / reports / feedback are welcome.__
