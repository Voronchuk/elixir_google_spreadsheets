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

  describe "range/4 span guard" do
    test "raises GSS.InvalidRange when the row span exceeds max_rows_per_request" do
      # default max_rows_per_request is 301; 400 - 1 = 399 >= 301
      assert_raise GSS.InvalidRange, fn ->
        GSS.Spreadsheet.range(1, 400, 1, 5)
      end
    end

    test "raises at the max_rows boundary (span == max_rows)" do
      # guard is `row_to - row_from >= max_rows()` with default 301;
      # 302 - 1 = 301 >= 301 -> raises
      assert_raise GSS.InvalidRange, fn ->
        GSS.Spreadsheet.range(1, 302, 1, 5)
      end
    end

    test "succeeds just under the max_rows boundary (span == max_rows - 1)" do
      # 301 - 1 = 300 < 301 -> allowed
      assert GSS.Spreadsheet.range(1, 301, 1, 5) == "A1:E301"
    end
  end
end
