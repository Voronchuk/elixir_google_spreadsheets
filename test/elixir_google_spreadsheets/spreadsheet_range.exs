defmodule GSS.SpreadsheetRangeTest do
  use ExUnit.Case, async: true

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

    test "generates range for multiple rows" do
      assert GSS.Spreadsheet.range(1, 10, 1, 10) == "A1:J10"
    end
  end
end
