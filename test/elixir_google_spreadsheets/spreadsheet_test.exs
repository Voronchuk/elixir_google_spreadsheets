defmodule GSS.SpreadsheetTest do
    use ExUnit.Case, async: true

    @test_spreadsheet_id Application.fetch_env!(:elixir_google_spreadsheets, :spreadsheet_id)
    @test_row1 ["1", "2", "3", "4", "5"]
    @test_row2 ["6", "1", "2", "3", "4", "0"]
    @test_row3 ["7", "7", "8"]

    setup context do
        {:ok, pid} = GSS.Spreadsheet.Supervisor.spreadsheet(@test_spreadsheet_id, name: context.test)
        on_exit fn ->
            cleanup_table(pid)
            :ok = Supervisor.terminate_child(GSS.Spreadsheet.Supervisor, pid)
        end
        {:ok, spreadsheet: pid}
    end

    @spec cleanup_table(pid) :: :ok
    defp cleanup_table(pid) do
        GSS.Spreadsheet.clear_row(pid, 1)
        GSS.Spreadsheet.clear_row(pid, 2)
        GSS.Spreadsheet.clear_row(pid, 3)
        GSS.Spreadsheet.clear_row(pid, 4)
    end


    test "initialize new spreadsheet process", %{spreadsheet: pid} do
        assert GSS.Registry.spreadsheet_pid(@test_spreadsheet_id) == pid
        assert GSS.Spreadsheet.id(pid) == @test_spreadsheet_id
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

    test "read batched for 2 rows", %{spreadsheet: pid} do
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

    describe "range/4 with one row" do
        test "generates range for length 14" do
            assert GSS.Spreadsheet.range(1, 1, 1, 14) == "A1:N1"
        end

        test "generates range for length 26" do
            assert GSS.Spreadsheet.range(1, 1, 1, 26) == "A1:Z1"
        end

        test "generates range for length 27" do
            assert GSS.Spreadsheet.range(1, 1, 1, 27) == "A1:AA1"
        end

        test "generates range for length 52" do
            assert GSS.Spreadsheet.range(1, 1, 1, 52) == "A1:AZ1"
        end

        test "generates range for length 53" do
            assert GSS.Spreadsheet.range(1, 1, 1, 53) == "A1:BA1"
        end

        test "genearates range for length 254" do
            assert GSS.Spreadsheet.range(1, 1, 1, 254) == "A1:IT1"
        end

        test "generates range for length 255" do
            assert GSS.Spreadsheet.range(1, 1, 1, 255) == "A1:IU1"
        end

        test "generates range for length 702" do
            assert GSS.Spreadsheet.range(1, 1, 1, 702) == "A1:ZZ1"
        end

        test "generates range for length 703" do
            assert GSS.Spreadsheet.range(1, 1, 1, 703) == "A1:AAA1"
        end
    end
end
