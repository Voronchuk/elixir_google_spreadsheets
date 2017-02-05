defmodule GSS do
    @moduledoc """
    Bootstrap Google Spreadsheet application.
    """

    use Application

    def start(_type, _args) do
        GSS.Supervisor.start_link()
    end
end
