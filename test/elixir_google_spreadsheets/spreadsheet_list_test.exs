defmodule GSS.SpreadsheetListTest do
  use ExUnit.Case, async: true

  @test_spreadsheet_id Application.compile_env!(:elixir_google_spreadsheets, :spreadsheet_id)
  @test_list "list space"
  @test_row1 ["1", "2", "3", "4", "5"]
  @test_row2 ["6", "1", "2", "3", "4", "0"]
  @test_row3 ["7", "7", "8"]

  setup context do
    {:ok, pid} =
      GSS.Spreadsheet.Supervisor.spreadsheet(@test_spreadsheet_id,
        name: context.test,
        list_name: @test_list
      )

    unless context[:skip_cleanup] do
      on_exit(fn ->
        cleanup_table(pid)
        :ok = DynamicSupervisor.terminate_child(GSS.Spreadsheet.Supervisor, pid)
      end)
    end

    {:ok, spreadsheet: pid}
  end

  @spec cleanup_table(pid) :: :ok
  defp cleanup_table(pid) do
    if Process.alive?(pid), do: GSS.Spreadsheet.clear_row(pid, 1)
    if Process.alive?(pid), do: GSS.Spreadsheet.clear_row(pid, 2)
    if Process.alive?(pid), do: GSS.Spreadsheet.clear_row(pid, 3)
    if Process.alive?(pid), do: GSS.Spreadsheet.clear_row(pid, 4)
    :ok
  end

  @tag :skip_cleanup
  test "initialize new spreadsheet list process", %{spreadsheet: pid} do
    assert GSS.Registry.spreadsheet_pid(@test_spreadsheet_id, list_name: @test_list) == pid
    assert GSS.Spreadsheet.id(pid) == @test_spreadsheet_id
    sheets = GSS.Spreadsheet.sheets(pid)
    assert Map.get(sheets, @test_list)
  end

  @tag :skip_cleanup
  test "read total number of filled rows in list", %{spreadsheet: pid} do
    {:ok, result} = GSS.Spreadsheet.rows(pid)
    assert result == 0
  end

  @tag :skip_cleanup
  test "read 5 columns from the 1 row in a spreadsheet list", %{spreadsheet: pid} do
    {:ok, result} = GSS.Spreadsheet.read_row(pid, 1, column_to: 5)
    assert result == ["", "", "", "", ""]
  end

  test "write new row lines in the end of document list", %{spreadsheet: pid} do
    :ok = GSS.Spreadsheet.write_row(pid, 1, @test_row1)
    :ok = GSS.Spreadsheet.write_row(pid, 2, @test_row2)
    {:ok, result} = GSS.Spreadsheet.read_row(pid, 1, column_to: 5)
    assert result == @test_row1
    {:ok, result} = GSS.Spreadsheet.read_row(pid, 2, column_to: 6)
    assert result == @test_row2
  end

  test "write some lines and append row between them on list", %{spreadsheet: pid} do
    :ok = GSS.Spreadsheet.write_row(pid, 1, @test_row1)
    :ok = GSS.Spreadsheet.write_row(pid, 2, @test_row2)
    :ok = GSS.Spreadsheet.append_row(pid, 1, @test_row3)
    {:ok, result} = GSS.Spreadsheet.read_row(pid, 3, column_to: 3)
    assert result == @test_row3
    {:ok, result} = GSS.Spreadsheet.read_row(pid, 2, column_to: 6)
    assert result == @test_row2
  end

  test "read batched for 2 rows in list", %{spreadsheet: pid} do
    {:ok, result} = GSS.Spreadsheet.read_rows(pid, 1, 2, column_to: 5)
    assert result == [nil, nil]
    {:ok, result} = GSS.Spreadsheet.read_rows(pid, 1, 2, column_to: 5, pad_empty: true)
    assert result == [["", "", "", "", ""], ["", "", "", "", ""]]
    :ok = GSS.Spreadsheet.write_row(pid, 1, @test_row1)
    {:ok, result} = GSS.Spreadsheet.read_rows(pid, 1, 2, column_to: 5, pad_empty: true)
    assert result == [@test_row1, ["", "", "", "", ""]]
    {:ok, result} = GSS.Spreadsheet.read_rows(pid, ["A1:E1", "A2:E2"])
    assert result == [@test_row1, nil]
    {:ok, result} = GSS.Spreadsheet.read_rows(pid, [1, 2], column_to: 5)
    assert result == [@test_row1, nil]
  end

  test "clear batched for 2 rows in list", %{spreadsheet: pid} do
    :ok = GSS.Spreadsheet.write_row(pid, 1, @test_row1)
    :ok = GSS.Spreadsheet.write_row(pid, 2, @test_row1)
    :ok = GSS.Spreadsheet.clear_rows(pid, ["A1:E1", "A2:E2"])
    {:ok, result} = GSS.Spreadsheet.read_rows(pid, 1, 2, column_to: 5)
    assert result == [nil, nil]
  end

  test "write batched for 2 rows in list", %{spreadsheet: pid} do
    {:ok, _} = GSS.Spreadsheet.write_rows(pid, ["A2:E2", "A3:F3"], [@test_row1, @test_row2])
    {:ok, result} = GSS.Spreadsheet.read_rows(pid, 2, 3, column_to: 6)
    assert result == [@test_row1 ++ [""], @test_row2]
  end

  @tag :skip_cleanup
  test "unexisting lists should gracefully fail" do
    {:ok, pid} =
      GSS.Spreadsheet.Supervisor.spreadsheet(@test_spreadsheet_id,
        name: :unknown_list,
        list_name: "unknown"
      )

    # Wait for the process to exit, capturing the exit message.
    monitor_ref = Process.monitor(pid)
    assert_receive {:DOWN, ^monitor_ref, :process, ^pid, "sheet list not found unknown"}, 5_000
  end
end
