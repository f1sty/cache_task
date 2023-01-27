defmodule Cache.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Cache,
      # {Registry, [keys: :unique, name: Cache.FunctionRegistry]},
      {Task.Supervisor, [name: Cache.TasksSupersisor]}
    ]

    opts = [strategy: :one_for_one, name: Cache.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
