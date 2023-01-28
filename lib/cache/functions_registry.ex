defmodule Cache.FunctionsRegistry do
  def start() do
    :ets.new(__MODULE__, [:set, :named_table, :public])
  end

  def register(key, fun, ttl) do
    entry = {key, fun, ttl}

    case :ets.insert_new(__MODULE__, entry) do
      false -> {:error, :already_registered}
      true -> :ok
    end
  end

  def get(key) do
    case :ets.match(__MODULE__, {key, :"$1", :"$2"}) do
      [] -> {:error, :not_registered}
      [[fun, ttl]] -> {:ok, {fun, ttl}}
    end
  end
end
