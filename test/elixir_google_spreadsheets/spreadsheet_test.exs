defmodule GSS.SpreadsheetTest do
  use ExUnit.Case, async: true

  @test_spreadsheet_id Application.fetch_env!(:elixir_google_spreadsheets, :spreadsheet_id)
  @test_row1 ["1", "2", "3", "4", "5"]
  @test_row2 ["6", "1", "2", "3", "4", "0"]
  @test_row3 ["7", "7", "8"]
  @test_row4 ["1", "4", "8", "4"]

  setup context do
    {:ok, pid} = GSS.Spreadsheet.Supervisor.spreadsheet(@test_spreadsheet_id, name: context.test)

    on_exit(fn ->
      cleanup_table(pid)
      :ok = DynamicSupervisor.terminate_child(GSS.Spreadsheet.Supervisor, pid)
    end)

    {:ok, spreadsheet: pid}
  end

  @spec cleanup_table(pid) :: :ok
  defp cleanup_table(pid) do
    GSS.Spreadsheet.clear_row(pid, 1)
    GSS.Spreadsheet.clear_row(pid, 2)
    GSS.Spreadsheet.clear_row(pid, 3)
    GSS.Spreadsheet.clear_row(pid, 4)
    GSS.Spreadsheet.clear_row(pid, 5)
  end

  test "initialize new spreadsheet process", %{spreadsheet: pid} do
    assert GSS.Registry.spreadsheet_pid(@test_spreadsheet_id) == pid
    assert GSS.Spreadsheet.id(pid) == @test_spreadsheet_id
  end

  test "should start only one for the same id", %{spreadsheet: pid} do
    {:ok, pid2} = GSS.Spreadsheet.Supervisor.spreadsheet(@test_spreadsheet_id)
    assert pid == pid2
  end

  test "read total number of filled rows", %{spreadsheet: pid} do
    {:ok, result} = GSS.Spreadsheet.rows(pid)
    assert result == 0
  end

  test "read 5 columns from the 1 row in a spreadsheet", %{spreadsheet: pid} do
    {:ok, result} = GSS.Spreadsheet.read_row(pid, 1, column_to: 5)
    assert result == ["", "", "", "", ""]
  end

  test "write new row lines in the end of document", %{spreadsheet: pid} do
    :ok = GSS.Spreadsheet.write_row(pid, 1, @test_row1)
    :ok = GSS.Spreadsheet.write_row(pid, 2, @test_row2)
    {:ok, result} = GSS.Spreadsheet.read_row(pid, 1, column_to: 5)
    assert result == @test_row1
    {:ok, result} = GSS.Spreadsheet.read_row(pid, 2, column_to: 6)
    assert result == @test_row2
  end

  test "write some lines and append row between them", %{spreadsheet: pid} do
    :ok = GSS.Spreadsheet.write_row(pid, 1, @test_row1)
    :ok = GSS.Spreadsheet.write_row(pid, 2, @test_row2)
    :ok = GSS.Spreadsheet.append_row(pid, 1, @test_row3)
    {:ok, result} = GSS.Spreadsheet.read_row(pid, 3, column_to: 3)
    assert result == @test_row3
    {:ok, result} = GSS.Spreadsheet.read_row(pid, 2, column_to: 6)
    assert result == @test_row2
  end

  test "write some lines and append two rows between them", %{spreadsheet: pid} do
    :ok = GSS.Spreadsheet.write_row(pid, 1, @test_row1)
    :ok = GSS.Spreadsheet.write_row(pid, 2, @test_row2)
    :ok = GSS.Spreadsheet.append_rows(pid, 1, [@test_row3, [nil], @test_row4])
    {:ok, result} = GSS.Spreadsheet.read_row(pid, 3, column_to: 3)
    assert result == @test_row3
    {:ok, result} = GSS.Spreadsheet.read_row(pid, 4, column_to: 1)
    assert result == [""]
    {:ok, result} = GSS.Spreadsheet.read_row(pid, 5, column_to: 4)
    assert result == @test_row4
    {:ok, result} = GSS.Spreadsheet.read_row(pid, 2, column_to: 6)
    assert result == @test_row2
  end

  test "read batched for 2 rows", %{spreadsheet: pid} do
    {:ok, result} = GSS.Spreadsheet.read_rows(pid, 1, 2, column_to: 5, batch_range: true)
    assert result == [nil, nil]
    {:ok, result} = GSS.Spreadsheet.read_rows(pid, 1, 2, column_to: 5, pad_empty: true)
    assert result == [["", "", "", "", ""], ["", "", "", "", ""]]
    :ok = GSS.Spreadsheet.write_row(pid, 2, @test_row1)
    {:ok, result} = GSS.Spreadsheet.read_rows(pid, 1, 3, column_to: 5, pad_empty: true)
    assert result == [["", "", "", "", ""], @test_row1, ["", "", "", "", ""]]
    {:ok, result} = GSS.Spreadsheet.read_rows(pid, ["A1:E1", "A2:E2", "A3:E3"])
    assert result == [nil, @test_row1, nil]
    {:ok, result} = GSS.Spreadsheet.read_rows(pid, [1, 2, 3], column_to: 5)
    assert result == [nil, @test_row1, nil]
  end

  test "read batched for only 1 row is possible", %{spreadsheet: pid} do
    {:ok, result} = GSS.Spreadsheet.read_rows(pid, 1, 1, column_to: 5)
    assert result == [nil]
  end

  test "read batched for 3 rows more then 1000 from start", %{spreadsheet: pid} do
    {:ok, result} = GSS.Spreadsheet.read_rows(pid, 1000, 1002, column_to: 5)
    assert result == [nil, nil, nil]
    :ok = GSS.Spreadsheet.write_row(pid, 1000, @test_row1)
    :ok = GSS.Spreadsheet.write_row(pid, 1001, @test_row1)
    :ok = GSS.Spreadsheet.write_row(pid, 1002, @test_row1)
    {:ok, result} = GSS.Spreadsheet.read_rows(pid, 1000, 1002, column_to: 5, pad_empty: true)
    assert result == [@test_row1, @test_row1, @test_row1]
    GSS.Spreadsheet.clear_row(pid, 1000)
    GSS.Spreadsheet.clear_row(pid, 1001)
    GSS.Spreadsheet.clear_row(pid, 1002)
  end

  test "read batched for 250 rows", %{spreadsheet: pid} do
    {:ok, result} = GSS.Spreadsheet.read_rows(pid, 2, 250, column_to: 26, batch_range: true)
    assert length(result) == 249
  end

  test "clear batched for 2 rows", %{spreadsheet: pid} do
    :ok = GSS.Spreadsheet.write_row(pid, 1, @test_row1)
    :ok = GSS.Spreadsheet.write_row(pid, 2, @test_row1)
    :ok = GSS.Spreadsheet.clear_rows(pid, 1, 2, column_to: 5)
    {:ok, result} = GSS.Spreadsheet.read_rows(pid, 1, 2, column_to: 5)
    assert result == [nil, nil]
  end

  test "write batched for 2 rows", %{spreadsheet: pid} do
    {:ok, _} = GSS.Spreadsheet.write_rows(pid, ["A2:E2", "A3:F3"], [@test_row1, @test_row2])
    {:ok, result} = GSS.Spreadsheet.read_rows(pid, 2, 3, column_to: 6)
    assert result == [@test_row1 ++ [""], @test_row2]
  end
end
