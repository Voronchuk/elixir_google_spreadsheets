defmodule GSS.Spreadsheet do
    @moduledoc """
    Model of Google Spreadsheet for external interaction.

    Maximum size of the supported canvas is 1000 x 26 cells.
    """

    require Logger
    use GenServer

    @typedoc """
    State of currently active Google spreadsheet:
        %{
            spreadsheet_id => "16Wgt0fuoYDgEAtGtYKF4jdjAhZez0q77UhkKdeKI6B4"
        }
    """
    @type state :: map()
    @type spreadsheet_data :: [String.t]
    @type spreadsheet_response :: {:json, map()} | {:error, Exception.t}

    @api_url_spreadsheet "https://sheets.googleapis.com/v4/spreadsheets/"


    @spec start_link(String.t, Keyword.t) :: {:ok, pid}
    def start_link(spreadsheet_id, opts) do
        GenServer.start_link(__MODULE__, spreadsheet_id, Keyword.take(opts, [:name]))
    end

    @spec init(String.t) :: {:ok, state}
    def init(spreadsheet_id) do
        {:ok, %{spreadsheet_id: spreadsheet_id}}
    end


    @doc """
    Client API calls.
    """
    @spec id(pid) :: String.t
    def id(pid) do
        GenServer.call(pid, :id)
    end

    @spec properties(pid) :: map()
    def properties(pid) do
        GenServer.call(pid, :properties)
    end

    @spec rows(pid) :: {:ok, Integer} | {:error, Exception.t}
    def rows(pid) do
        GenServer.call(pid, :rows)
    end

    @spec fetch(pid, String.t) :: {:ok, spreadsheet_data} | {:error, Exception.t}
    def fetch(pid, range) do
        GenServer.call(pid, {:fetch, range})
    end

    @spec read_row(pid, Integer, Keyword.t) :: {:ok, spreadsheet_data} | {:error, Exception.t}
    def read_row(pid, row_index, options \\ []) do
        GenServer.call(pid, {:read_row, row_index, options})
    end

    @spec write_row(pid, Integer, spreadsheet_data, Keyword.t) :: :ok
    def write_row(pid, row_index, column_list, options \\ []) when is_list(column_list) do
        GenServer.call(pid, {:write_row, row_index, column_list, options})
    end

    @spec append_row(pid, Integer, spreadsheet_data, Keyword.t) :: :ok
    def append_row(pid, row_index, column_list, options \\ []) when is_list(column_list) do
        GenServer.call(pid, {:append_row, row_index, column_list, options})
    end

    @spec clear_row(pid, Integer, Keyword.t) :: :ok
    def clear_row(pid, row_index, options \\ []) do
        GenServer.call(pid, {:clear_row, row_index, options})
    end


    @doc """
    Get shreadsheet id stored in this state.
    Used mainly for testing purposes.
    """
    def handle_call(:id, _from, %{spreadsheet_id: spreadsheet_id} = state) do
        {:reply, spreadsheet_id, state}
    end

    @doc """
    Get the shreadsheet properties
    """
    def handle_call(:properties, _from, %{spreadsheet_id: spreadsheet_id} = state) do
      query = spreadsheet_id

      case spreadsheet_query(:get, query) do
        {:json, properties} ->
          {:reply, {:ok, properties}, state}
        {:error, exception} ->
          {:reply, {:error, exception}, state}
        end
    end

    @doc """
    Get total number of rows from spreadsheets.
    """
    def handle_call(:rows, _from, %{spreadsheet_id: spreadsheet_id} = state) do
        query = "#{spreadsheet_id}/values/#{range(1, 1000, 1, 1)}"

        case spreadsheet_query(:get, query) do
            {:json, %{"values" => values}} ->
                {:reply, {:ok, length(values)}, state}
            {:json, _} ->
                {:reply, {:ok, 0}, state}
            {:error, exception} ->
                {:reply, {:error, exception}, state}
        end
    end

    @doc """
    Fetch the given range of cells from the spreadsheet
    """
    def handle_call({:fetch, the_range}, _from, %{spreadsheet_id: spreadsheet_id} = state) do
        query = "#{spreadsheet_id}/values/#{the_range}"

        case spreadsheet_query(:get, query) do
            {:json, %{"values" => values}} ->
                {:reply, {:ok, values}, state}
            {:json, _} ->
                {:reply, {:ok, nil}, state}
            {:error, exception} ->
                {:reply, {:error, exception}, state}
        end
    end


    @doc """
    Get column value list for specific row from a spreadsheet.
    """
    def handle_call(
        {:read_row, row_index, options},
        _from,
        %{spreadsheet_id: spreadsheet_id} = state
    ) do
        major_dimension = Keyword.get(options, :major_dimension, "ROWS")
        value_render_option = Keyword.get(options, :value_render_option, "FORMATTED_VALUE")
        datetime_render_option = Keyword.get(options, :datetime_render_option, "FORMATTED_STRING")

        column_from = Keyword.get(options, :column_from, 1)
        column_to = Keyword.get(options, :column_to, 25)
        range = range(row_index, row_index, column_from, column_to)
        query = "#{spreadsheet_id}/values/#{range}" <>
            "?majorDimension=#{major_dimension}&valueRenderOption=#{value_render_option}" <>
            "&dateTimeRenderOption=#{datetime_render_option}"

        case spreadsheet_query(:get, query) do
            {:json, %{"values" => [values]}} when length(values) >= column_to ->
                {:reply, {:ok, values}, state}
            {:json, %{"values" => [values]}} ->
                pad_amount = column_to - length(values)
                {:reply, {:ok, values ++ pad(pad_amount)}, state}
            {:json, _} ->
                {:reply, {:ok, pad(column_to)}, state}
            {:error, exception} ->
                {:reply, {:error, exception}, state}
        end
    end

    @doc """
    Write values in a specific row to a spreadsheet.
    """
    def handle_call(
        {:write_row, row_index, column_list, options},
        _from,
        %{spreadsheet_id: spreadsheet_id} = state
    ) do
        value_input_option = Keyword.get(options, :value_render_option, "USER_ENTERED")

        write_cells_count = length(column_list)
        column_from = Keyword.get(options, :column_from, 1)
        column_to = Keyword.get(options, :column_to, column_from + write_cells_count - 1)
        range = range(row_index, row_index, column_from, column_to)
        query = "#{spreadsheet_id}/values/#{range}?valueInputOption=#{value_input_option}"

        case spreadsheet_query(:put, query, column_list, options ++ [range: range]) do
            {:json, %{"updatedRows" => 1, "updatedColumns" => updated_columns}}
            when updated_columns == write_cells_count ->
                {:reply, :ok, state}
            {:error, exception} ->
                {:reply, {:error, exception}, state}
        end
    end

    @doc """
    Insert row under some other row and write the column_list content there.
    """
    def handle_call(
        {:append_row, row_index, column_list, options},
        _from,
        %{spreadsheet_id: spreadsheet_id} = state
    ) do
        value_input_option = Keyword.get(options, :value_render_option, "USER_ENTERED")
        insert_data_option = Keyword.get(options, :insert_data_option, "INSERT_ROWS")

        write_cells_count = length(column_list)
        column_from = Keyword.get(options, :column_from, 1)
        column_to = Keyword.get(options, :column_to, column_from + write_cells_count - 1)
        range = range(row_index, row_index, column_from, column_to)
        query = "#{spreadsheet_id}/values/#{range}:append" <>
            "?valueInputOption=#{value_input_option}&insertDataOption=#{insert_data_option}"

        case spreadsheet_query(:post, query, column_list, options ++ [range: range]) do
            {:json, %{"updates" => %{
                "updatedRows" => 1, "updatedColumns" => updated_columns
            }}} when updated_columns == write_cells_count ->
                {:reply, :ok, state}
            {:error, exception} ->
                {:reply, {:error, exception}, state}
        end
    end

    @doc """
    Clear rows in spreadsheet by their index.
    """
    def handle_call(
        {:clear_row, row_index, options},
        _from,
        %{spreadsheet_id: spreadsheet_id} = state
    ) do
        column_from = Keyword.get(options, :column_from, 1)
        column_to = Keyword.get(options, :column_to, 25)
        range = range(row_index, row_index, column_from, column_to)
        query = "#{spreadsheet_id}/values/#{range}:clear"

        case spreadsheet_query(:post, query) do
            {:json, %{"clearedRange" => _}} ->
                {:reply, :ok, state}
            {:error, exception} ->
                {:reply, {:error, exception}, state}
        end
    end


    @spec spreadsheet_query(:get | :post, String.t) :: spreadsheet_response
    defp spreadsheet_query(type, url_suffix) when is_atom(type) do
        headers = %{"Authorization" => "Bearer #{GSS.Registry.token}"}
        HTTPoison.start
        response = case type do
            :get ->
                HTTPoison.get! @api_url_spreadsheet <> url_suffix, headers
            :post ->
                HTTPoison.post! @api_url_spreadsheet <> url_suffix, "", headers
        end
        spreadsheet_query_response(response)
    end
    @spec spreadsheet_query(:post | :put, String.t, spreadsheet_data, Keyword.t) :: spreadsheet_response
    defp spreadsheet_query(type, url_suffix, data, options) when is_atom(type) do
        headers = %{"Authorization" => "Bearer #{GSS.Registry.token}"}
        HTTPoison.start

        response = case type do
            :post ->
                body = spreadsheet_query_body(data, options)
                HTTPoison.post! @api_url_spreadsheet <> url_suffix, body, headers
            :put ->
                body = spreadsheet_query_body(data, options)
                HTTPoison.put! @api_url_spreadsheet <> url_suffix, body, headers
        end
        spreadsheet_query_response(response)
    end

    @spec spreadsheet_query_response(%HTTPoison.Response{}) :: spreadsheet_response
    defp spreadsheet_query_response(response) do
        case response do
            %{status_code: 200, body: body} ->
                json = Poison.decode!(body)
                {:json, json}
            _ ->
                Logger.error fn -> "Spreadsheet query: #{response}" end
                {:error, GSS.GoogleApiError}
        end
    end

    @spec spreadsheet_query_body(spreadsheet_data, Keyword.t) :: String.t
    defp spreadsheet_query_body(data, options) do
        range = Keyword.fetch!(options, :range)
        major_dimension = Keyword.get(options, :major_dimension, "ROWS")
        Poison.encode! %{
            range: range,
            majorDimension: major_dimension,
            values: [data]
        }
    end

    @spec range(Integer, Integer, Integer, Integer) :: String.t
    def range(row_from, row_to, column_from, column_to)
    when row_from <= row_to and column_from <= column_to
    and row_to < 1001 do
        column_from_letter = col_index_to_letter(column_from)
        column_to_letter = col_index_to_letter(column_to)
        "#{column_from_letter}#{row_from}:#{column_to_letter}#{row_to}"
    end
    def range(_, _, _, _) do
        raise GSS.InvalidRange,
            message: "Max rows 1000, max columns 255, `to` value should be greater then `from`"
    end

    @spec pad(Integer) :: spreadsheet_data
    defp pad(amount) do
        for _i <- 1..amount, do: ""
    end

    @spec col_index_to_letter(Integer) :: String.t
    defp col_index_to_letter(index) do
        case index do
          i when i > 0 and i < 27 ->
            to_string([64 + index])
          i when i > 26 and i < 256 ->
            to_string([64 + div(index, 26), 64 + rem(index, 26)])
            _ ->
                raise GSS.InvalidColumnIndex, message: "Invalid column index"
        end
    end
end
