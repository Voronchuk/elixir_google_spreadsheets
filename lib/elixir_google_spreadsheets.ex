defmodule GSS do
    @moduledoc """
    Bootstrap Google Spreadsheet application.
    """

    @spec start() :: {:ok, pid}
    def start do
        GSS.Supervisor.start_link()
    end
end
