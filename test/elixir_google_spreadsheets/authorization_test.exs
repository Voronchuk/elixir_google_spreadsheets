defmodule GSS.AuthorizationTest do
    use ExUnit.Case, async: true

    test "fetch account access token to work with Google Spreadsheets" do
        assert GSS.Registry.token
    end
end
