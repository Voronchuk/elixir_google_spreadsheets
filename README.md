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
6. Add `{:elixir_google_spreadsheets, "~> 0.1.7"}` to __mix.exs__ under `deps` function, add `:elixir_google_spreadsheets` in your application list.
7. Add __service_account.json__ in your `config.exs` or other config file, like `dev.exs` or `prod.secret.exs`.
    config :goth,
        json: "./config/service_account.json" |> File.read!
8. Run `mix deps.get && mix deps.compile`.

## API limits
For the non-default Google API limits, you can tune the following settings locally:

```
config :elixir_google_spreadsheets, :client,
  request_workers: 50,
  max_demand: 100,
  max_interval: :timer.minutes(1),
  interval: 100
```

# OTP 20
Currently (01.07.2017) there is an issue in OTP 20, because `:crypto.mpint/1` was moved to another module and it's used in `:goth` dependency `:json_web_token`, you can use this temporary hack as a resolution, by adding this in your deps: `{:json_web_token, git: "https://github.com/starbuildr/json_web_token_ex.git", override: true}`

# Usage
Initialise spreadsheet thread with it's id which you can fetch from URL:

    `{:ok, pid} = GSS.Spreadsheet.Supervisor.spreadsheet("XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX-XXXXXXXXX")`

Or if you wish to edit only a specific list:

    `{:ok, pid} = GSS.Spreadsheet.Supervisor.spreadsheet("XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX-XXXXXXXXX", list_name: "my_list3")`

Sample operations:

* `GSS.Spreadsheet.id(pid)`
* `GSS.Spreadsheet.rows(pid)`
* `GSS.Spreadsheet.read_row(pid, 1, column_to: 5)`
* `GSS.Spreadsheet.read_rows(pid, 1, 10, column_to: 5, pad_empty: true)`
* `GSS.Spreadsheet.read_rows(pid, [1, 3, 5], column_to: 5, pad_empty: true)`
* `GSS.Spreadsheet.read_rows(pid, ["A1:E1", "A2:E2"])`
* `GSS.Spreadsheet.write_row(pid, 1, ["1", "2", "3", "4", "5"])`
* `GSS.Spreadsheet.write_rows(pid, ["A2:E2", "A3:F3"], [["1", "2", "3", "4", "5"], ["1", "2", "3", "4", "5", "6"]])`
* `GSS.Spreadsheet.append_row(pid, 1, ["1", "2", "3", "4", "5"])`
* `GSS.Spreadsheet.clear_row(pid, 1)`
* `GSS.Spreadsheet.clear_rows(pid, 1, 10)`
* `GSS.Spreadsheet.clear_rows(pid, ["A1:E1", "A2:E2"])`

Last function param of `GSS.Spreadsheet` function calls support the same `Keyword` options (in snake_case instead of camelCase), as defined in [Google API Docs](https://developers.google.com/sheets/reference/rest/v4/spreadsheets.values).

We also define `column_from` and `column_to` Keyword options which control range of cell which will be queried.

Default values:
* `column_from = 1`
* `column_to = 26`
* `major_dimension = "ROWS"`
* `value_render_option = "FORMATTED_VALUE"`
* `datetime_render_option = "FORMATTED_STRING"`
* `value_render_option = "USER_ENTERED"`
* `insert_data_option = "INSERT_ROWS"`

# Restrictions
* Max columns __26__, max rows __1000__;
* __This library is in it's early beta, use on your own risk. Pull requests / reports / feedback are welcome.__
