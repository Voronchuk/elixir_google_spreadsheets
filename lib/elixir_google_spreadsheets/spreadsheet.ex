defmodule GSS.Spreadsheet do
  @moduledoc """
  Model of Google Spreadsheet for external interaction.
  """

  require Logger
  use GenServer
  alias GSS.Client

  @typedoc """
  State of currently active Google spreadsheet:
      %{
          spreadsheet_id => "16Wgt0fuoYDgEAtGtYKF4jdjAhZez0q77UhkKdeKI6B4",
          list_name => nil,
          sheet_id => nil
      }
  """
  @type state :: map()
  @type spreadsheet_data :: [String.t()]
  @type spreadsheet_response :: {:json, map()} | {:error, Exception.t()} | no_return()
  @type grid_range :: %{
          row_from: integer(),
          row_to: integer(),
          col_from: integer(),
          col_to: integer()
        }

  @api_url_spreadsheet "https://sheets.googleapis.com/v4/spreadsheets/"

  @max_rows GSS.config(:max_rows_per_request, 301)
  @default_column_from GSS.config(:default_column_from, 1)
  @default_column_to GSS.config(:default_column_to, 26)

  @spec start_link(String.t(), Keyword.t()) :: {:ok, pid}
  def start_link(spreadsheet_id, opts) do
    GenServer.start_link(__MODULE__, {spreadsheet_id, opts}, Keyword.take(opts, [:name]))
  end

  @spec init({String.t(), Keyword.t()}) :: {:ok, state}
  def init({spreadsheet_id, opts}) do
    {:ok, %{spreadsheet_id: spreadsheet_id, list_name: Keyword.get(opts, :list_name)}}
  end

  @doc """
  Get spreadsheet internal id.
  """
  @spec id(pid) :: String.t()
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
  Get sheet id associated with list_name in state.
  """
  @spec get_sheet_id(pid) :: {:ok, integer()}
  def get_sheet_id(pid), do: GenServer.call(pid, :get_sheet_id)

  @doc """
  Add the sheet id associated with the list_name to the state.
  """
  @spec add_sheet_id_to_state(pid) :: {:ok, nil}
  def add_sheet_id_to_state(pid), do: {:ok, nil} = GenServer.call(pid, :add_sheet_id_to_state)

  @doc """
  Get spreadsheet sheets from properties.
  """
  @spec sheets(pid, Keyword.t()) :: [map()] | map()
  def sheets(pid, options \\ []) do
    with {:ok, %{"sheets" => sheets}} <- gen_server_call(pid, :properties, options),
         {:is_raw_response?, false, _} <-
           {:is_raw_response?, Keyword.get(options, :raw, false), sheets} do
      Enum.reduce(sheets, %{}, fn %{"properties" => %{"title" => title} = properties}, acc ->
        Map.put(acc, title, properties)
      end)
    else
      {:is_raw_response?, false, sheets} ->
        sheets

      _ ->
        []
    end
  end

  @doc """
  Get total amount of rows in a spreadsheet.
  """
  @spec rows(pid, Keyword.t()) :: {:ok, integer()} | {:error, Exception.t()}
  def rows(pid, options \\ []) do
    gen_server_call(pid, :rows, options)
  end

  @spec update_sheet_size(pid, integer(), integer(), Keyword.t()) ::
          {:ok, list()} | {:error, Exception.t()}
  def update_sheet_size(pid, row_count, col_count, options \\ []) do
    gen_server_call(pid, {:update_sheet_size, row_count, col_count, options}, options)
  end

  @doc """
  Granular read by a custom range from a spreadsheet.
  """
  @spec fetch(pid, String.t()) :: {:ok, spreadsheet_data} | {:error, Exception.t()}
  def fetch(pid, range) do
    GenServer.call(pid, {:fetch, range})
  end

  @doc """
  Read row in a spreadsheet by index.
  """
  @spec read_row(pid, integer(), Keyword.t()) :: {:ok, spreadsheet_data} | {:error, Exception.t()}
  def read_row(pid, row_index, options \\ []) do
    gen_server_call(pid, {:read_row, row_index, options}, options)
  end

  @doc """
  Override row in a spreadsheet by index.
  """
  @spec write_row(pid, integer(), spreadsheet_data, Keyword.t()) :: :ok
  def write_row(pid, row_index, column_list, options \\ []) when is_list(column_list) do
    gen_server_call(pid, {:write_row, row_index, column_list, options}, options)
  end

  @doc """
  Append row in a spreadsheet after an index.
  """
  @spec append_row(pid, integer(), spreadsheet_data, Keyword.t()) :: :ok
  def append_row(pid, row_index, [cell | _] = column_list, options \\ [])
      when is_binary(cell) or is_nil(cell) do
    gen_server_call(pid, {:append_rows, row_index, [column_list], options}, options)
  end

  @doc """
  Clear row in a spreadsheet by index.
  """
  @spec clear_row(pid, integer(), Keyword.t()) :: :ok
  def clear_row(pid, row_index, options \\ []) do
    gen_server_call(pid, {:clear_row, row_index, options}, options)
  end

  @doc """
  Batched read, which returns more than one record.
  Pass either an array of ranges (or rows), or start and end row indexes.

  By default it returns `nils` for an empty rows,
  use `pad_empty: true` and `column_to: integer` options to fill records
  with an empty string values.
  """
  @spec read_rows(pid, [String.t()] | [integer()]) ::
          {:ok, [spreadsheet_data | nil]} | {:error, Exception.t()}
  def read_rows(pid, ranges), do: read_rows(pid, ranges, [])

  @spec read_rows(pid, [String.t()] | [integer()], Keyword.t()) ::
          {:ok, [spreadsheet_data]} | {:error, Exception.t()}
  def read_rows(pid, ranges, options) when is_list(ranges) do
    gen_server_call(pid, {:read_rows, ranges, options}, options)
  end

  @spec read_rows(pid, integer(), integer()) :: {:ok, [spreadsheet_data]} | {:error, atom}
  def read_rows(pid, row_index_start, row_index_end)
      when is_integer(row_index_start) and is_integer(row_index_end),
      do: read_rows(pid, row_index_start, row_index_end, [])

  def read_rows(_, _, _),
    do: {:error, %GSS.InvalidInput{message: "invalid start or end row index"}}

  @spec read_rows(pid, integer(), integer(), Keyword.t()) ::
          {:ok, [spreadsheet_data]} | {:error, atom}
  def read_rows(pid, row_index_start, row_index_end, options)
      when is_integer(row_index_start) and is_integer(row_index_end) and
             row_index_start < row_index_end do
    gen_server_call(pid, {:read_rows, row_index_start, row_index_end, options}, options)
  end

  def read_rows(_, _, _, _),
    do: {:error, %GSS.InvalidInput{message: "invalid start or end row index"}}

  @doc """
  Batched clear, which deletes more then one record.
  Pass either an array of ranges, or start and end row indexes.
  """
  @spec clear_rows(pid, [String.t()]) :: :ok | {:error, Exception.t()}
  def clear_rows(pid, ranges), do: clear_rows(pid, ranges, [])
  @spec clear_rows(pid, [String.t()], Keyword.t()) :: :ok | {:error, Exception.t()}
  def clear_rows(pid, ranges, options) when is_list(ranges) do
    gen_server_call(pid, {:clear_rows, ranges, options}, options)
  end

  @spec clear_rows(pid, integer(), integer()) :: :ok | {:error, Exception.t()}
  def clear_rows(pid, row_index_start, row_index_end)
      when is_integer(row_index_start) and is_integer(row_index_end),
      do: clear_rows(pid, row_index_start, row_index_end, [])

  def clear_rows(_, _, _),
    do: {:error, %GSS.InvalidInput{message: "invalid start or end row index"}}

  @spec clear_rows(pid, integer(), integer(), Keyword.t()) :: :ok | {:error, Exception.t()}
  def clear_rows(pid, row_index_start, row_index_end, options)
      when is_integer(row_index_start) and is_integer(row_index_end) and
             row_index_start < row_index_end do
    gen_server_call(pid, {:clear_rows, row_index_start, row_index_end, options}, options)
  end

  def clear_rows(_, _, _, _),
    do: {:error, %GSS.InvalidInput{message: "invalid start or end row index"}}

  @doc """
  Batch update to write multiple rows.

  Range schema should define the same amount of rows as
  amound of records in data and same amount of columns
  as entries in data record.
  """
  @spec write_rows(pid, [String.t()], [spreadsheet_data], Keyword.t()) ::
          {:ok, list()} | {:error, Exception.t()}
  def write_rows(pid, ranges, data, opts \\ [])

  def write_rows(pid, ranges, data, options)
      when is_list(data) and is_list(ranges) and length(data) == length(ranges) do
    gen_server_call(pid, {:write_rows, ranges, data, options}, options)
  end

  def write_rows(_, _, _, _),
    do:
      {:error,
       %GSS.InvalidInput{
         message: "invalid ranges or data, length of ranges and data lists should be the same"
       }}

  @doc """
  Batch update to append multiple rows.
  """
  @spec append_rows(pid, integer(), [spreadsheet_data], Keyword.t()) ::
          :ok | {:error, Exception.t()}
  def append_rows(pid, row_index, [[cell | _] | _] = data, options \\ [])
      when (is_binary(cell) or is_nil(cell)) and row_index > 0 do
    gen_server_call(pid, {:append_rows, row_index, data, options}, options)
  end

  @doc """
  Set Basic Filter.

  Two options for `params`:
  - To not filter out any rows, pass an empty map.
  - To filter out rows based on a column value, add these
    keys: `col_idx`, `condition_type`, `user_entered_value`.
  """
  @spec set_basic_filter(pid, grid_range(), map(), Keyword.t()) ::
          {:ok, list()} | {:error, Exception.t()}
  def set_basic_filter(pid, grid_range, params, opts \\ [])

  def set_basic_filter(pid, grid_range, params, options) do
    gen_server_call(pid, {:set_basic_filter, grid_range, params, options}, options)
  end

  @doc """
  Clear Basic Filter.
  """
  @spec clear_basic_filter(pid) :: {:ok, map()} | {:error, Exception.t()}
  def clear_basic_filter(pid, opts \\ [])

  def clear_basic_filter(pid, options) do
    gen_server_call(pid, {:clear_basic_filter, options}, options)
  end

  @doc """
  Freeze Row or Column Header.

  Required keys in `params`:
  - `dim`: Either `:row` or `:col` to set the dimension to freeze.
  - `n_freeze`: Set the number of rows or columns to freeze.
  """
  @spec freeze_header(pid, %{dim: :row | :col, n_freeze: integer()}, Keyword.t()) ::
          {:ok, list()} | {:error, Exception.t()}
  def freeze_header(pid, params, opts \\ [])

  def freeze_header(pid, params, options) do
    gen_server_call(pid, {:freeze_header, params, options}, options)
  end

  @doc """
  Update Column Width.

  Required keys in `params`:
  - `col_idx`: Index of column.
  - `col_width`: Column width in pixels.
  """
  @spec update_col_width(pid, %{col_idx: integer(), col_width: integer()}, Keyword.t()) ::
          {:ok, list()} | {:error, Exception.t()}
  def update_col_width(pid, params, opts \\ [])

  def update_col_width(pid, params, options) do
    gen_server_call(pid, {:update_col_width, params, options}, options)
  end

  @doc """
  Add Number Format.

  Required keys in `params`:
  - `type`: The number format of the cell (e.g., `DATE` or `TIME`).
  - `pattern`: Pattern string used for formatting (e.g., `yyyy-mm-dd`).
  """
  @spec add_number_format(
          pid,
          grid_range(),
          %{type: String.t(), pattern: String.t()},
          Keyword.t()
        ) ::
          {:ok, list()} | {:error, Exception.t()}
  def add_number_format(pid, grid_range, params, opts \\ [])

  def add_number_format(pid, grid_range, params, options) do
    gen_server_call(pid, {:add_number_format, grid_range, params, options}, options)
  end

  @doc """
  Update Column Wrap.

  Required keys in `params`:
  - `wrap_strategy`: How to wrap text in a cell. Options: [`overflow_cell`, `clip`, `wrap`].
  """
  @spec update_col_wrap(pid, grid_range(), %{wrap_strategy: String.t()}, Keyword.t()) ::
          {:ok, list()} | {:error, Exception.t()}
  def update_col_wrap(pid, grid_range, params, opts \\ [])

  def update_col_wrap(pid, grid_range, params, options) do
    gen_server_call(pid, {:update_col_wrap, grid_range, params, options}, options)
  end

  @doc """
  Set Font.

  Required keys in `params`: `font_family`.
  """
  @spec set_font(pid, grid_range(), %{font_family: String.t()}, Keyword.t()) ::
          {:ok, list()} | {:error, Exception.t()}
  def set_font(pid, grid_range, params, opts \\ [])

  def set_font(pid, grid_range, params, options) do
    gen_server_call(pid, {:set_font, grid_range, params, options}, options)
  end

  @doc """
  Add Conditional Formula using a boolean rule (as opposed to a gradient rule).

  Required keys in `params`:
  - `formula`: A value the condition is based on. The value is parsed as if the user
    typed into a cell. Formulas are supported (and must begin with an = or a '+').
  - `color_map`: Represents a color in the RGBA color space. Keys are `red`,
    `green`, `blue`, and `alpha`, and each value is in the interval [0, 1].
  """
  @spec add_conditional_format(
          pid,
          grid_range(),
          %{formula: String.t(), color_map: map()},
          Keyword.t()
        ) ::
          {:ok, list()} | {:error, Exception.t()}
  def add_conditional_format(pid, grid_range, params, opts \\ [])

  def add_conditional_format(pid, grid_range, params, options) do
    gen_server_call(pid, {:add_conditional_format, grid_range, params, options}, options)
  end

  @doc """
  Update Border.

  Map `params` can only have keys in `[:top, :bottom, :left, :right]`. If a key is omitted,
  then the border remains as-is on that side. Subkeys: `style`, `red`, `green`, `blue`, `alpha`.
  """
  @spec update_border(pid, grid_range(), map(), Keyword.t()) ::
          {:ok, list()} | {:error, Exception.t()}
  def update_border(pid, grid_range, params, opts \\ [])

  def update_border(pid, grid_range, params, options) do
    gen_server_call(pid, {:update_border, grid_range, params, options}, options)
  end

  # Get spreadsheet id stored in this state.
  # Used mainly for testing purposes.
  def handle_call(:id, _from, %{spreadsheet_id: spreadsheet_id} = state) do
    {:reply, spreadsheet_id, state}
  end

  # Get the spreadsheet properties
  def handle_call(:properties, _from, %{spreadsheet_id: spreadsheet_id} = state) do
    query = spreadsheet_id

    case spreadsheet_query(:get, query) do
      {:json, properties} ->
        {:reply, {:ok, properties}, state}

      {:error, exception} ->
        {:reply, {:error, exception}, state}
    end
  end

  # Get the sheet id from state.
  # Used mainly in Spreadsheet.Supervisor.spreadsheet/2.
  def handle_call(:get_sheet_id, _from, %{sheet_id: sheet_id} = state) when is_nil(sheet_id) do
    {:reply, {:ok, nil}, state}
  end

  def handle_call(:get_sheet_id, _from, %{sheet_id: sheet_id} = state) do
    {:reply, {:ok, sheet_id}, state}
  end

  # Add the sheet id associated with the list_name to the state.
  def handle_call(:add_sheet_id_to_state, _from, %{list_name: list_name} = state)
      when is_nil(list_name) do
    {:reply, {:ok, nil}, state}
  end

  def handle_call(:add_sheet_id_to_state, from, %{list_name: list_name} = state) do
    with {:reply, {:ok, %{"sheets" => sheets}}, state} <- handle_call(:properties, from, state) do
      [sheet_id] =
        Enum.filter(sheets, fn %{"properties" => %{"title" => title}} -> title == list_name end)
        |> Enum.map(fn %{"properties" => %{"sheetId" => sheet_id}} -> sheet_id end)

      {:reply, {:ok, nil}, Map.put(state, :sheet_id, sheet_id)}
    else
      {:error, exception} -> {:reply, {:error, exception}, state}
    end
  end

  # Get total number of rows from spreadsheets.
  def handle_call(:rows, _from, %{spreadsheet_id: spreadsheet_id} = state) do
    query = "#{spreadsheet_id}/values/#{maybe_attach_list(state)}A1:B"

    case spreadsheet_query(:get, query) do
      {:json, %{"values" => values}} ->
        {:reply, {:ok, length(values)}, state}

      {:json, _} ->
        {:reply, {:ok, 0}, state}

      {:error, exception} ->
        {:reply, {:error, exception}, state}
    end
  end

  def handle_call(
        {:update_sheet_size, row_count, col_count, options},
        _from,
        %{spreadsheet_id: spreadsheet_id, sheet_id: sheet_id} = state
      ) do
    request_body = %{
      requests: [
        %{
          updateSheetProperties: %{
            fields: "gridProperties",
            properties: %{
              sheetId: sheet_id,
              gridProperties: %{rowCount: row_count, columnCount: col_count}
            }
          }
        }
      ]
    }

    batch_update_query(spreadsheet_id, request_body, options, state)
  end

  # Fetch the given range of cells from the spreadsheet
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

  # Get column value list for specific row from a spreadsheet.
  def handle_call(
        {:read_row, row_index, options},
        _from,
        %{spreadsheet_id: spreadsheet_id} = state
      ) do
    major_dimension = Keyword.get(options, :major_dimension, "ROWS")
    value_render_option = Keyword.get(options, :value_render_option, "FORMATTED_VALUE")
    datetime_render_option = Keyword.get(options, :datetime_render_option, "FORMATTED_STRING")

    column_from = Keyword.get(options, :column_from, @default_column_from)
    column_to = Keyword.get(options, :column_to, @default_column_to)
    range = range(row_index, row_index, column_from, column_to)

    query =
      "#{spreadsheet_id}/values/#{maybe_attach_list(state)}#{range}" <>
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

  # Write values in a specific row to a spreadsheet.
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
      when updated_columns > 0 ->
        {:reply, :ok, state}

      {:error, exception} ->
        {:reply, {:error, exception}, state}
    end
  end

  # Insert row under some other row and write the column_list content there.
  def handle_call(
        {:append_rows, row_index, column_lists, options},
        _from,
        %{spreadsheet_id: spreadsheet_id} = state
      ) do
    value_input_option = Keyword.get(options, :value_input_option, "USER_ENTERED")
    insert_data_option = Keyword.get(options, :insert_data_option, "INSERT_ROWS")

    write_cells_count = Enum.map(column_lists, &Kernel.length/1) |> Enum.max()
    row_count = length(column_lists)
    row_max_index = row_index + row_count - 1
    column_from = Keyword.get(options, :column_from, 1)
    column_to = Keyword.get(options, :column_to, column_from + write_cells_count - 1)
    range = range(row_index, row_max_index, column_from, column_to, state)

    query =
      "#{spreadsheet_id}/values/#{range}:append" <>
        "?valueInputOption=#{value_input_option}&insertDataOption=#{insert_data_option}"

    case spreadsheet_query(
           :post,
           query,
           column_lists,
           options ++ [range: range, wrap_data: false]
         ) do
      {:json,
       %{
         "updates" => %{
           "updatedRows" => updated_rows,
           "updatedColumns" => updated_columns
         }
       }}
      when updated_columns > 0 and updated_rows > 0 ->
        {:reply, :ok, state}

      {:error, exception} ->
        {:reply, {:error, exception}, state}
    end
  end

  # Clear rows in spreadsheet by their index.
  def handle_call(
        {:clear_row, row_index, options},
        _from,
        %{spreadsheet_id: spreadsheet_id} = state
      ) do
    column_from = Keyword.get(options, :column_from, @default_column_from)
    column_to = Keyword.get(options, :column_to, @default_column_to)
    range = range(row_index, row_index, column_from, column_to)
    query = "#{spreadsheet_id}/values/#{maybe_attach_list(state)}#{range}:clear"

    case spreadsheet_query(:post, query) do
      {:json, %{"clearedRange" => _}} ->
        {:reply, :ok, state}

      {:error, exception} ->
        {:reply, {:error, exception}, state}
    end
  end

  # Get column value list for specific row from a spreadsheet.
  def handle_call({:read_rows, [row | _] = rows, options}, from, state) when is_integer(row) do
    column_from = Keyword.get(options, :column_from, @default_column_from)
    column_to = Keyword.get(options, :column_to, @default_column_to)

    ranges =
      Enum.map(rows, fn row_index ->
        range(row_index, row_index, column_from, column_to)
      end)

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
    batched_ranges = Keyword.get(options, :batched_ranges, ranges)

    str_ranges =
      batched_ranges
      |> Enum.map(&{:ranges, "#{maybe_attach_list(state)}#{&1}"})
      |> URI.encode_query()

    query =
      "#{spreadsheet_id}/values:batchGet" <>
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
    column_from = Keyword.get(options, :column_from, @default_column_from)
    column_to = Keyword.get(options, :column_to, @default_column_to)

    options =
      if Keyword.get(options, :batch_range, true) do
        batched_range = range(row_index_start, row_index_end, column_from, column_to)

        options
        |> Keyword.put(:batched_ranges, [batched_range])
        |> Keyword.put(:batched_rows, row_index_end - row_index_start + 1)
      else
        options
      end

    ranges =
      Enum.map(row_index_start..row_index_end, fn row_index ->
        range(row_index, row_index, column_from, column_to)
      end)

    handle_call({:read_rows, ranges, options}, from, state)
  end

  # Clear rows in spreadsheet by their index.
  def handle_call(
        {:clear_rows, ranges, _options},
        _from,
        %{spreadsheet_id: spreadsheet_id} = state
      ) do
    str_ranges =
      ranges
      |> Enum.map(&{:ranges, "#{maybe_attach_list(state)}#{&1}"})
      |> URI.encode_query()

    query = "#{spreadsheet_id}/values:batchClear?#{str_ranges}"

    case spreadsheet_query(:post, query) do
      {:json, %{"clearedRanges" => _}} ->
        {:reply, :ok, state}

      {:error, exception} ->
        {:reply, {:error, exception}, state}
    end
  end

  def handle_call({:clear_rows, row_index_start, row_index_end, options}, from, state) do
    column_from = Keyword.get(options, :column_from, @default_column_from)
    column_to = Keyword.get(options, :column_to, @default_column_to)

    ranges =
      Enum.map(row_index_start..row_index_end, fn row_index ->
        range(row_index, row_index, column_from, column_to)
      end)

    handle_call({:clear_rows, ranges, options}, from, state)
  end

  # Write values in batch based on a ranges schema.
  def handle_call(
        {:write_rows, ranges, data, options},
        _from,
        %{spreadsheet_id: spreadsheet_id} = state
      ) do
    request_data =
      Enum.map(Enum.zip(ranges, data), fn {range, record} ->
        %{
          range: "#{maybe_attach_list(state)}#{range}",
          values: [record],
          majorDimension: Keyword.get(options, :major_dimension, "ROWS")
        }
      end)

    request_body = %{
      data: request_data,
      valueInputOption: Keyword.get(options, :value_input_option, "USER_ENTERED")
      # includeValuesInResponse: Keyword.get(options, :include_values_in_response, false),
      # responseValueRenderOption: Keyword.get(options, :response_value_render_option, "FORMATTED_VALUE"),
      # responseDateTimeRenderOption: Keyword.get(options, :response_date_time_render_option, "SERIAL_NUMBER")
    }

    query = "#{spreadsheet_id}/values:batchUpdate"

    case spreadsheet_query_post_batch(query, request_body, options) do
      {:json, %{"responses" => responses}} ->
        {:reply, {:ok, responses}, state}

      {:error, exception} ->
        {:reply, {:error, exception}, state}
    end
  end

  def handle_call(
        {:set_basic_filter, grid_range, params, options},
        _from,
        %{spreadsheet_id: spreadsheet_id, sheet_id: sheet_id} = state
      ) do
    request = %{
      setBasicFilter: %{
        filter: Map.merge(%{range: grid_range(sheet_id, grid_range)}, filter_specs(params))
      }
    }

    request_body = %{requests: [request]}
    batch_update_query(spreadsheet_id, request_body, options, state)
  end

  def handle_call(
        {:clear_basic_filter, options},
        _from,
        %{spreadsheet_id: spreadsheet_id, sheet_id: sheet_id} = state
      ) do
    request_body = %{requests: [%{clearBasicFilter: %{sheetId: sheet_id}}]}
    batch_update_query(spreadsheet_id, request_body, options, state)
  end

  def handle_call(
        {:freeze_header, %{dim: dim, n_freeze: n_freeze}, options},
        _from,
        %{spreadsheet_id: spreadsheet_id, sheet_id: sheet_id} = state
      ) do
    row_col = if dim == :col, do: "frozenColumnCount", else: "frozenRowCount"

    request = %{
      updateSheetProperties: %{
        properties: %{
          sheetId: sheet_id,
          gridProperties: %{String.to_atom(row_col) => n_freeze}
        },
        fields: "gridProperties." <> row_col
      }
    }

    request_body = %{requests: [request]}
    batch_update_query(spreadsheet_id, request_body, options, state)
  end

  def handle_call(
        {:update_col_width, %{col_idx: col_idx, col_width: col_width}, options},
        _from,
        %{spreadsheet_id: spreadsheet_id, sheet_id: sheet_id} = state
      ) do
    request = %{
      updateDimensionProperties: %{
        range: %{
          sheetId: sheet_id,
          dimension: "COLUMNS",
          startIndex: col_idx,
          endIndex: col_idx + 1
        },
        properties: %{pixelSize: col_width},
        fields: "pixelSize"
      }
    }

    request_body = %{requests: [request]}
    batch_update_query(spreadsheet_id, request_body, options, state)
  end

  def handle_call(
        {:add_number_format, grid_range, %{type: type, pattern: pattern}, options},
        _from,
        %{spreadsheet_id: spreadsheet_id, sheet_id: sheet_id} = state
      ) do
    request = %{
      repeatCell: %{
        range: grid_range(sheet_id, grid_range),
        fields: "userEnteredFormat.numberFormat",
        cell: %{
          userEnteredFormat: %{numberFormat: %{type: String.upcase(type), pattern: pattern}}
        }
      }
    }

    request_body = %{requests: [request]}
    batch_update_query(spreadsheet_id, request_body, options, state)
  end

  def handle_call(
        {:update_col_wrap, grid_range, %{wrap_strategy: wrap_strategy}, options},
        _from,
        %{spreadsheet_id: spreadsheet_id, sheet_id: sheet_id} = state
      ) do
    request = %{
      repeatCell: %{
        range: grid_range(sheet_id, grid_range),
        fields: "userEnteredFormat.wrapStrategy",
        cell: %{wrapStrategy: String.upcase(wrap_strategy)}
      }
    }

    request_body = %{requests: [request]}
    batch_update_query(spreadsheet_id, request_body, options, state)
  end

  def handle_call(
        {:set_font, grid_range, %{font_family: font_family}, options},
        _from,
        %{spreadsheet_id: spreadsheet_id, sheet_id: sheet_id} = state
      ) do
    request = %{
      repeatCell: %{
        range: grid_range(sheet_id, grid_range),
        fields: "userEnteredFormat.textFormat",
        cell: %{userEnteredFormat: %{textFormat: %{fontFamily: font_family}}}
      }
    }

    request_body = %{requests: [request]}
    batch_update_query(spreadsheet_id, request_body, options, state)
  end

  def handle_call(
        {:add_conditional_format, grid_range, %{formula: formula, color_map: color_map}, options},
        _from,
        %{spreadsheet_id: spreadsheet_id, sheet_id: sheet_id} = state
      ) do
    request = %{
      addConditionalFormatRule: %{
        rule: %{
          ranges: [grid_range(sheet_id, grid_range)],
          booleanRule: %{
            condition: %{type: "CUSTOM_FORMULA", values: [%{userEnteredValue: formula}]},
            format: %{backgroundColor: color_map}
          }
        }
      }
    }

    request_body = %{requests: [request]}
    batch_update_query(spreadsheet_id, request_body, options, state)
  end

  def handle_call(
        {:update_border, grid_range, params, options},
        _from,
        %{spreadsheet_id: spreadsheet_id, sheet_id: sheet_id} = state
      ) do
    range = %{range: grid_range(sheet_id, grid_range)}

    border =
      Enum.reduce(params, %{}, fn {k, %{red: r, green: g, blue: b, alpha: a, style: s}}, acc ->
        case k in [:top, :bottom, :left, :right] do
          true ->
            border_v = %{
              style: String.upcase(s),
              colorStyle: %{rgbColor: %{red: r, green: g, blue: b, alpha: a}}
            }

            Map.put(acc, k, border_v)

          false ->
            raise GSS.InvalidInput,
              message: "Map key `#{k}` in params must be one of `[:top, :bottom, :left, :right]`"
        end
      end)

    request_body = %{requests: [%{updateBorders: Map.merge(range, border)}]}
    batch_update_query(spreadsheet_id, request_body, options, state)
  end

  def filter_specs(%{}), do: %{}

  def filter_specs(%{col_idx: col, condition_type: type, user_entered_value: value}) do
    %{
      filterSpecs: [
        %{
          columnIndex: col,
          filterCriteria: %{condition: %{type: type, values: [%{userEnteredValue: value}]}}
        }
      ]
    }
  end

  def filter_specs(_) do
    raise GSS.InvalidInput,
      message:
        "Map `params` must either be empty or contain keys: `col_idx`, `condition_type`, `user_entered_value`"
  end

  def batch_update_query(spreadsheet_id, request_body, options, state) do
    query = "#{spreadsheet_id}:batchUpdate"

    case spreadsheet_query_post_batch(query, request_body, options) do
      {:json, %{"replies" => replies, "spreadsheetId" => _}} ->
        {:reply, {:ok, replies}, state}

      {:error, exception} ->
        {:reply, {:error, exception}, state}
    end
  end

  @spec spreadsheet_query(:get | :post, String.t()) :: spreadsheet_response
  defp spreadsheet_query(type, url_suffix) when is_atom(type) do
    headers = %{"Authorization" => "Bearer #{GSS.Registry.token()}"}
    params = get_request_params()
    response = Client.request(type, @api_url_spreadsheet <> url_suffix, "", headers, params)
    spreadsheet_query_response(response)
  end

  @spec spreadsheet_query(:post | :put, String.t(), spreadsheet_data, Keyword.t()) ::
          spreadsheet_response
  defp spreadsheet_query(type, url_suffix, data, options) when is_atom(type) do
    headers = %{"Authorization" => "Bearer #{GSS.Registry.token()}"}
    params = get_request_params()

    response =
      case type do
        :post ->
          body = spreadsheet_query_body(data, options)
          Client.request(:post, @api_url_spreadsheet <> url_suffix, body, headers, params)

        :put ->
          body = spreadsheet_query_body(data, options)
          Client.request(:put, @api_url_spreadsheet <> url_suffix, body, headers, params)
      end

    spreadsheet_query_response(response)
  end

  @spec spreadsheet_query_post_batch(String.t(), map(), Keyword.t()) :: spreadsheet_response
  defp spreadsheet_query_post_batch(url_suffix, request, _options) do
    headers = %{"Authorization" => "Bearer #{GSS.Registry.token()}"}
    params = get_request_params()
    body = Poison.encode!(request)
    response = Client.request(:post, @api_url_spreadsheet <> url_suffix, body, headers, params)
    spreadsheet_query_response(response)
  end

  @spec spreadsheet_query_response({:ok | :error, %HTTPoison.Response{}}) :: spreadsheet_response
  defp spreadsheet_query_response(response) do
    with {:ok, %{status_code: 200, body: body}} <- response,
         {:ok, json} <- Poison.decode(body) do
      {:json, json}
    else
      {:ok, %{status_code: status_code, body: body}} when status_code != 200 ->
        Logger.error("Google API returned status code: #{status_code}. Body: #{body}")
        {:error, %GSS.GoogleApiError{message: "invalid google API status code #{status_code}"}}

      {:error, reason} ->
        Logger.error(fn -> "Spreadsheet query: #{inspect(reason)}" end)
        {:error, %GSS.GoogleApiError{message: "invalid google API response #{inspect(reason)}"}}
    end
  end

  @spec spreadsheet_query_body(spreadsheet_data, Keyword.t()) :: String.t() | no_return()
  defp spreadsheet_query_body(data, options) do
    range = Keyword.fetch!(options, :range)
    major_dimension = Keyword.get(options, :major_dimension, "ROWS")
    wrap_data = Keyword.get(options, :wrap_data, true)

    Poison.encode!(%{
      range: range,
      majorDimension: major_dimension,
      values: if(wrap_data, do: [data], else: data)
    })
  end

  @spec range(integer(), integer(), integer(), integer()) :: String.t()
  def range(row_from, row_to, column_from, column_to)
      when row_from <= row_to and column_from <= column_to and row_to - row_from < @max_rows do
    column_from_letters = col_number_to_letters(column_from)
    column_to_letters = col_number_to_letters(column_to)
    "#{column_from_letters}#{row_from}:#{column_to_letters}#{row_to}"
  end

  def range(_, _, _, _) do
    raise GSS.InvalidRange,
      message: "Max rows #{@max_rows}, `to` value should be greater than `from`"
  end

  @spec range(integer(), integer(), integer(), integer(), state) :: String.t()
  def range(row_from, row_to, column_from, column_to, state) do
    maybe_attach_list(state) <> range(row_from, row_to, column_from, column_to)
  end

  @doc """
  Combine the sheet_id into the grid_range, and drop any values from the range that are nil.
  """
  @spec grid_range(integer(), grid_range()) :: map()
  def grid_range(sheet_id, %{row_from: rf, row_to: rt, col_from: cf, col_to: ct}) do
    %{
      sheetId: sheet_id,
      startRowIndex: rf,
      endRowIndex: rt,
      startColumnIndex: cf,
      endColumnIndex: ct
    }
    |> Map.filter(fn {_k, v} -> v != nil end)
  end

  @spec pad(integer()) :: spreadsheet_data
  defp pad(amount) do
    for _i <- 1..amount, do: ""
  end

  @spec col_number_to_letters(integer()) :: String.t()
  def col_number_to_letters(col_number) do
    indices = index_to_index_list(col_number - 1)
    charlist = for i <- indices, do: i + ?A
    to_string(charlist)
  end

  defp index_to_index_list(index, list \\ [])

  defp index_to_index_list(index, list) when index >= 26 do
    index_to_index_list(div(index, 26) - 1, [rem(index, 26) | list])
  end

  defp index_to_index_list(index, list) when index >= 0 and index < 26 do
    [index | list]
  end

  @spec maybe_attach_list(state) :: String.t()
  defp maybe_attach_list(%{list_name: nil}), do: ""

  defp maybe_attach_list(%{list_name: list_name}) when is_bitstring(list_name),
    do: "#{list_name}!"

  @spec parse_value_ranges([map()], Keyword.t()) :: [[String.t()] | nil]
  defp parse_value_ranges(value_ranges, options) do
    column_to = Keyword.get(options, :column_to)
    parse_value_ranges(value_ranges, options, column_to)
  end

  @spec parse_value_ranges([map()], Keyword.t(), integer() | nil) :: [[String.t()] | nil]
  defp parse_value_ranges(value_ranges, options, column_to)
       when is_integer(column_to) or is_nil(column_to) do
    total_rows = Keyword.get(options, :batched_rows, 1)
    pad_empty = Keyword.get(options, :pad_empty, false)
    response = Enum.flat_map(value_ranges, &parse_value(&1, column_to, pad_empty))

    if length(response) < total_rows do
      padding = List.duplicate(empty_row(column_to, pad_empty), total_rows - length(response))
      response ++ padding
    else
      response
    end
  end

  @spec parse_value(map(), integer() | nil, boolean()) :: [[String.t()] | nil]
  defp parse_value(%{"values" => values}, column_to, _)
       when is_list(values) and is_integer(column_to) do
    Enum.map(values, &value_range_block_wrapper(&1, column_to))
  end

  defp parse_value(%{"values" => values}, _, false) when is_list(values), do: values
  defp parse_value(_, column_to, pad_empty), do: [empty_row(column_to, pad_empty)]

  @spec empty_row(integer() | nil, boolean()) :: [String.t()] | nil
  defp empty_row(nil, true), do: []
  defp empty_row(column_to, true), do: pad(column_to)
  defp empty_row(_, false), do: nil

  @spec value_range_block_wrapper([String.t()], integer()) :: [String.t()]
  defp value_range_block_wrapper(values, column_to) when length(values) >= column_to, do: values

  defp value_range_block_wrapper(values, column_to) do
    pad_amount = column_to - length(values)
    values ++ pad(pad_amount)
  end

  @spec get_request_params() :: Keyword.t()
  defp get_request_params do
    params = Client.config(:request_opts, [])
    Keyword.merge(params, [
      ssl: [
        versions: [:"tlsv1.2"],
        verify: :verify_peer,
        depth: 99,
        cacerts: :certifi.cacerts(),
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ],
        reuse_sessions: false,
        crl_check: true,
        crl_cache: {:ssl_crl_cache, {:internal, [http: 30000]}}
      ]
    ])
  end

  defp gen_server_call(pid, tuple, options) do
    case Keyword.get(options, :timeout) do
      nil ->
        GenServer.call(pid, tuple)

      timeout ->
        GenServer.call(pid, tuple, timeout)
    end
  end
end
