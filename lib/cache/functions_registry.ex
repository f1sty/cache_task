defmodule Cache.FunctionsRegistry do
  def start() do
    :ets.new(Table, [:set, :named_table, :public])
  end

  def register(key, fun, ttl) do
    entry = {key, fun, ttl}

    case :ets.insert_new(Table, entry) do
      false -> {:error, :already_registered}
      true -> :ok
    end
  end

  def get(key) do
    case :ets.match(Table, {key, :"$1", :"$2"}) do
      [] -> {:error, :not_registered}
      [return] -> {:ok, return}
    end
  end
end
