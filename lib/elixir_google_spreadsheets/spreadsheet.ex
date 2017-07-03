defmodule GSS.Spreadsheet do
    @moduledoc """
    Model of Google Spreadsheet for external interaction.

    Maximum size of the supported canvas is 1000 x 26 cells.
    """

    require Logger
    use GenServer
    alias GSS.Client

    @typedoc """
    State of currently active Google spreadsheet:
        %{
            spreadsheet_id => "16Wgt0fuoYDgEAtGtYKF4jdjAhZez0q77UhkKdeKI6B4",
            list_name => nil
        }
    """
    @type state :: map()
    @type spreadsheet_data :: [String.t]
    @type spreadsheet_response :: {:json, map()} | {:error, Exception.t} | no_return()

    @api_url_spreadsheet "https://sheets.googleapis.com/v4/spreadsheets/"


    @spec start_link(String.t, Keyword.t) :: {:ok, pid}
    def start_link(spreadsheet_id, opts) do
        GenServer.start_link(__MODULE__, {spreadsheet_id, opts}, Keyword.take(opts, [:name]))
    end

    @spec init({String.t, Keyword.t}) :: {:ok, state}
    def init({spreadsheet_id, opts}) do
        {:ok, %{spreadsheet_id: spreadsheet_id, list_name: Keyword.get(opts, :list_name)}}
    end

    @doc """
    Get spreadsheet internal id.
    """
    @spec id(pid) :: String.t
    def id(pid) do
        GenServer.call(pid, :id)
    end

    @doc """
    Get spreadsheet properties.
    """
    @spec properties(pid) :: map()
    def properties(pid) do
        GenServer.call(pid, :properties)
    end

    @doc """
    Get total amount of rows in a spreadsheet.
    """
    @spec rows(pid) :: {:ok, integer()} | {:error, Exception.t}
    def rows(pid) do
        GenServer.call(pid, :rows)
    end

    @doc """
    Granural read by a custom range from a spreadsheet.
    """
    @spec fetch(pid, String.t) :: {:ok, spreadsheet_data} | {:error, Exception.t}
    def fetch(pid, range) do
        GenServer.call(pid, {:fetch, range})
    end

    @doc """
    Read row in a spreadsheet by index.
    """
    @spec read_row(pid, integer(), Keyword.t) :: {:ok, spreadsheet_data} | {:error, Exception.t}
    def read_row(pid, row_index, options \\ []) do
        GenServer.call(pid, {:read_row, row_index, options})
    end

    @doc """
    Override row in a spreadsheet by index.
    """
    @spec write_row(pid, integer(), spreadsheet_data, Keyword.t) :: :ok
    def write_row(pid, row_index, column_list, options \\ []) when is_list(column_list) do
        GenServer.call(pid, {:write_row, row_index, column_list, options})
    end

    @doc """
    Append row in a spreadsheet after an index.
    """
    @spec append_row(pid, integer(), spreadsheet_data, Keyword.t) :: :ok
    def append_row(pid, row_index, column_list, options \\ []) when is_list(column_list) do
        GenServer.call(pid, {:append_row, row_index, column_list, options})
    end

    @doc """
    Clear row in a spreadsheet by index.
    """
    @spec clear_row(pid, integer(), Keyword.t) :: :ok
    def clear_row(pid, row_index, options \\ []) do
        GenServer.call(pid, {:clear_row, row_index, options})
    end

    @doc """
    Batched read, which returns more then one record.
    Pass either an array of ranges (or rows), or start and end row indexes.

    By default it returns `nils` for an empty rows,
    use `pad_empty: true` and `column_to: integer` options to fill records
    with an empty string values.
    """
    @spec read_rows(pid, [String.t] | [integer()]) :: {:ok, [spreadsheet_data | nil]} | {:error, Exception.t}
    def read_rows(pid, ranges), do: read_rows(pid, ranges, [])
    @spec read_rows(pid, [String.t] | [integer()], Keyword.t) :: {:ok, [spreadsheet_data]} | {:error, Exception.t}
    def read_rows(pid, ranges, options) when is_list(ranges) do
        GenServer.call(pid, {:read_rows, ranges, options})
    end
    @spec read_rows(pid, integer(), integer()) :: {:ok, [spreadsheet_data]} | {:error, Exception.t}
    def read_rows(pid, row_index_start, row_index_end)
    when is_integer(row_index_start) and is_integer(row_index_end), do: read_rows(pid, row_index_start, row_index_end, [])
    def read_rows(_, _, _), do: {:error, GSS.InvalidInput}
    @spec read_rows(pid, integer(), integer(), Keyword.t) :: {:ok, [spreadsheet_data]} | {:error, Exception.t}
    def read_rows(pid, row_index_start, row_index_end, options)
    when is_integer(row_index_start) and is_integer(row_index_end) and row_index_start < row_index_end do
        GenServer.call(pid, {:read_rows, row_index_start, row_index_end, options})
    end
    def read_rows(_, _, _, _), do: {:error, GSS.InvalidInput}

    @doc """
    Batched clear, which deletes more then one record.
    Pass either an array of ranges, or start and end row indexes.
    """
    @spec clear_rows(pid, [String.t]) :: :ok | {:error, Exception.t}
    def clear_rows(pid, ranges), do: clear_rows(pid, ranges, [])
    @spec clear_rows(pid, [String.t], Keyword.t) :: :ok | {:error, Exception.t}
    def clear_rows(pid, ranges, options) when is_list(ranges) do
        GenServer.call(pid, {:clear_rows, ranges, options})
    end
    @spec clear_rows(pid, integer(), integer()) :: :ok | {:error, Exception.t}
    def clear_rows(pid, row_index_start, row_index_end)
    when is_integer(row_index_start) and is_integer(row_index_end), do: clear_rows(pid, row_index_start, row_index_end, [])
    def clear_rows(_, _, _), do: {:error, GSS.InvalidInput}
    @spec clear_rows(pid, integer(), integer(), Keyword.t) :: :ok | {:error, Exception.t}
    def clear_rows(pid, row_index_start, row_index_end, options)
    when is_integer(row_index_start) and is_integer(row_index_end) and row_index_start < row_index_end do
        GenServer.call(pid, {:clear_rows, row_index_start, row_index_end, options})
    end
    def clear_rows(_, _, _, _), do: {:error, GSS.InvalidInput}

    @doc """
    Batch update to write multiple rows.

    Range schema should define the same amount of rows as
    amound of records in data and same amount of columns
    as entries in data record.
    """
    @spec write_rows(pid, [String.t], [spreadsheet_data]) :: :ok
    def write_rows(pid, ranges, data), do: write_rows(pid, ranges, data, [])
    @spec write_rows(pid, [String.t], [spreadsheet_data], Keyword.t) :: :ok
    def write_rows(pid, ranges, data, options)
    when is_list(data) and is_list(ranges) and length(data) == length(ranges) do
        GenServer.call(pid, {:write_rows, ranges, data, options})
    end
    def write_rows(_, _, _, _), do: {:error, GSS.InvalidInput}


    @doc """
    Get shreadsheet id stored in this state.
    Used mainly for testing purposes.
    """
    def handle_call(:id, _from, %{spreadsheet_id: spreadsheet_id} = state) do
        {:reply, spreadsheet_id, state}
    end
    def handle_call(:id, _from, state) do
        IO.inspect state
      {:no_reply, state}
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
        query = "#{spreadsheet_id}/values/#{maybe_attach_list(state)}#{range(1, 1000, 1, 1)}"

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
        query = "#{spreadsheet_id}/values/#{maybe_attach_list(state)}#{the_range}"

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
        column_to = Keyword.get(options, :column_to, 26)
        range = range(row_index, row_index, column_from, column_to)
        query = "#{spreadsheet_id}/values/#{maybe_attach_list(state)}#{range}" <>
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
        value_input_option = Keyword.get(options, :value_input_option, "USER_ENTERED")

        write_cells_count = length(column_list)
        column_from = Keyword.get(options, :column_from, 1)
        column_to = Keyword.get(options, :column_to, column_from + write_cells_count - 1)
        range = range(row_index, row_index, column_from, column_to, state)
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
        value_input_option = Keyword.get(options, :value_input_option, "USER_ENTERED")
        insert_data_option = Keyword.get(options, :insert_data_option, "INSERT_ROWS")

        write_cells_count = length(column_list)
        column_from = Keyword.get(options, :column_from, 1)
        column_to = Keyword.get(options, :column_to, column_from + write_cells_count - 1)
        range = range(row_index, row_index, column_from, column_to, state)
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
        column_to = Keyword.get(options, :column_to, 26)
        range = range(row_index, row_index, column_from, column_to)
        query = "#{spreadsheet_id}/values/#{maybe_attach_list(state)}#{range}:clear"

        case spreadsheet_query(:post, query) do
            {:json, %{"clearedRange" => _}} ->
                {:reply, :ok, state}
            {:error, exception} ->
                {:reply, {:error, exception}, state}
        end
    end


    @doc """
    Get column value list for specific row from a spreadsheet.
    """
    def handle_call({:read_rows, [row | _] = rows, options}, from, state) when is_integer(row) do
        column_from = Keyword.get(options, :column_from, 1)
        column_to = Keyword.get(options, :column_to, 26)
        ranges = Enum.map rows, fn(row_index) ->
            range(row_index, row_index, column_from, column_to)
        end
        handle_call({:read_rows, ranges, options}, from, state)
    end
    def handle_call(
        {:read_rows, ranges, options},
        _from,
        %{spreadsheet_id: spreadsheet_id} = state
    ) do
        major_dimension = Keyword.get(options, :major_dimension, "ROWS")
        value_render_option = Keyword.get(options, :value_render_option, "FORMATTED_VALUE")
        datetime_render_option = Keyword.get(options, :datetime_render_option, "FORMATTED_STRING")

        str_ranges = ranges
        |> Enum.map(&("ranges=#{maybe_attach_list(state)}#{&1}"))
        |> Enum.join("&")
        query = "#{spreadsheet_id}/values:batchGet" <>
            "?majorDimension=#{major_dimension}&valueRenderOption=#{value_render_option}" <>
            "&dateTimeRenderOption=#{datetime_render_option}&#{str_ranges}"

        case spreadsheet_query(:get, query) do
            {:json, %{"valueRanges" => valueRanges}} ->
                {:reply, {:ok, parse_value_ranges(valueRanges, options)}, state}
            {:json, _} ->
                {:reply, {:ok, []}, state}
            {:error, exception} ->
                {:reply, {:error, exception}, state}
        end
    end
    def handle_call({:read_rows, row_index_start, row_index_end, options}, from, state) do
        column_from = Keyword.get(options, :column_from, 1)
        column_to = Keyword.get(options, :column_to, 26)
        ranges = Enum.map row_index_start..row_index_end, fn(row_index) ->
            range(row_index, row_index, column_from, column_to)
        end
        handle_call({:read_rows, ranges, options}, from, state)
    end


    @doc """
    Clear rows in spreadsheet by their index.
    """
    def handle_call(
        {:clear_rows, ranges, _options},
        _from,
        %{spreadsheet_id: spreadsheet_id} = state
    ) do
        str_ranges = ranges
        |> Enum.map(&("ranges=#{maybe_attach_list(state)}#{&1}"))
        |> Enum.join("&")
        query = "#{spreadsheet_id}/values:batchClear?#{str_ranges}"

        case spreadsheet_query(:post, query) do
            {:json, %{"clearedRanges" => _}} ->
                {:reply, :ok, state}
            {:error, exception} ->
                {:reply, {:error, exception}, state}
        end
    end
    def handle_call({:clear_rows, row_index_start, row_index_end, options}, from, state) do
        column_from = Keyword.get(options, :column_from, 1)
        column_to = Keyword.get(options, :column_to, 26)
        ranges = Enum.map row_index_start..row_index_end, fn(row_index) ->
            range(row_index, row_index, column_from, column_to)
        end
        handle_call({:clear_rows, ranges, options}, from, state)
    end


    @doc """
    Write values in batch based on a ranges schema.
    """
    def handle_call(
        {:write_rows, ranges, data, options},
        _from,
        %{spreadsheet_id: spreadsheet_id} = state
    ) do
        request_data = Enum.map Enum.zip(ranges, data), fn({range, record}) ->
            %{
                range: "#{maybe_attach_list(state)}#{range}",
                values: [record],
                majorDimension: Keyword.get(options, :major_dimension, "ROWS")
            }
        end

        request_body = %{
            data: request_data,
            valueInputOption: Keyword.get(options, :value_input_option, "USER_ENTERED"),
            #includeValuesInResponse: Keyword.get(options, :include_values_in_response, false),
            #responseValueRenderOption: Keyword.get(options, :response_value_render_option, "FORMATTED_VALUE"),
            #responseDateTimeRenderOption: Keyword.get(options, :response_date_time_render_option, "SERIAL_NUMBER")
        }

        query = "#{spreadsheet_id}/values:batchUpdate"
        case spreadsheet_query_post_batch(query, request_body, options) do
            {:json, %{"responses" => responses}} ->
                {:reply, {:ok, responses}, state}
            {:error, exception} ->
                {:reply, {:error, exception}, state}
        end
    end

    @spec spreadsheet_query(:get | :post, String.t) :: spreadsheet_response
    defp spreadsheet_query(type, url_suffix) when is_atom(type) do
        headers = %{"Authorization" => "Bearer #{GSS.Registry.token}"}
        params = [ssl: [{:versions, [:'tlsv1.2']}]]
        response = Client.request(type, @api_url_spreadsheet <> url_suffix, "", headers, params)
        spreadsheet_query_response(response)
    end
    @spec spreadsheet_query(:post | :put, String.t, spreadsheet_data, Keyword.t) :: spreadsheet_response
    defp spreadsheet_query(type, url_suffix, data, options) when is_atom(type) do
        headers = %{"Authorization" => "Bearer #{GSS.Registry.token}"}
        params = [ssl: [{:versions, [:'tlsv1.2']}]]
        response = case type do
            :post ->
                body = spreadsheet_query_body(data, options)
                Client.request(:post, @api_url_spreadsheet <> url_suffix, body, headers, params)
            :put ->
                body = spreadsheet_query_body(data, options)
                Client.request(:put, @api_url_spreadsheet <> url_suffix, body, headers, params)
        end
        spreadsheet_query_response(response)
    end
    @spec spreadsheet_query_post_batch(String.t, map(), Keyword.t) :: spreadsheet_response
    defp spreadsheet_query_post_batch(url_suffix, request, _options) do
        headers = %{"Authorization" => "Bearer #{GSS.Registry.token}"}
        body = Poison.encode!(request)
        response = Client.request(:post, @api_url_spreadsheet <> url_suffix, body, headers)
        spreadsheet_query_response(response)
    end

    @spec spreadsheet_query_response({:ok | :error, %HTTPoison.Response{}}) :: spreadsheet_response
    defp spreadsheet_query_response(response) do
        with {:ok, %{status_code: 200, body: body}} <- response,
             {:ok, json} <- Poison.decode(body) do
             {:json, json}
        else
            {:error, reason}->
                Logger.error fn -> "Spreadsheet query: #{inspect(reason)}" end
                {:error, GSS.GoogleApiError}
        end
    end

    @spec spreadsheet_query_body(spreadsheet_data, Keyword.t) :: String.t | no_return()
    defp spreadsheet_query_body(data, options) do
        range = Keyword.fetch!(options, :range)
        major_dimension = Keyword.get(options, :major_dimension, "ROWS")
        Poison.encode! %{
            range: range,
            majorDimension: major_dimension,
            values: [data]
        }
    end

    @spec range(integer(), integer(), integer(), integer()) :: String.t
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
    @spec range(integer(), integer(), integer(), integer(), state) :: String.t
    def range(row_from, row_to, column_from, column_to, state) do
        maybe_attach_list(state) <> range(row_from, row_to, column_from, column_to)
    end

    @spec pad(integer()) :: spreadsheet_data
    defp pad(amount) do
        for _i <- 1..amount, do: ""
    end

    @spec col_index_to_letter(integer()) :: String.t
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

    @spec maybe_attach_list(state) :: String.t
    defp maybe_attach_list(%{list_name: nil}), do: ""
    defp maybe_attach_list(%{list_name: list_name}) when is_bitstring(list_name), do: "#{list_name}!"

    @spec parse_value_ranges([map()], Keyword.t) :: [[String.t | nil]]
    defp parse_value_ranges(value_ranges, options) do
        column_to = Keyword.get(options, :column_to)
        parse_value_ranges(value_ranges, options, column_to)
    end
    @spec parse_value_ranges([map()], Keyword.t, integer() | nil) :: [[String.t | nil]]
    defp parse_value_ranges(value_ranges, options, nil) do
        Enum.map value_ranges, fn(value_range) ->
            case value_range do
                %{"values" => [values]} ->
                    values
                _ ->
                    if Keyword.get(options, :pad_empty, false) do
                        []
                    else
                        nil
                    end
            end
        end
    end
    defp parse_value_ranges(value_ranges, options, column_to) when is_integer(column_to) do
        Enum.map value_ranges, fn(value_range) ->
            case value_range do
                %{"values" => [values]} when length(values) >= column_to ->
                    values
                %{"values" => [values]} ->
                    pad_amount = column_to - length(values)
                    values ++ pad(pad_amount)
                _ ->
                    if Keyword.get(options, :pad_empty, false) do
                        pad(column_to)
                    else
                        nil
                    end
            end
        end
    end
end
