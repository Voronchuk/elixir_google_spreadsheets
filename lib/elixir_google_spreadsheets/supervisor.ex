defmodule GSS.Supervisor do
  @moduledoc """
  Supervisor tree to keep track of registry and spreadsheet supervisor.
  """

  use Supervisor

  @spec init([]) :: {:ok, {:supervisor.sup_flags(), [Supervisor.Spec.spec()]}} | :ignore
  def init([]) do
    children = [
      {GSS.Registry, []},
      {GSS.Spreadsheet.Supervisor, []},
      {GSS.Client.Supervisor, []}
    ]

    Supervisor.start_link(children, [strategy: :one_for_all, name: __MODULE__])
  end
end
