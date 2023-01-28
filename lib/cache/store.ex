defmodule Cache.Store do
  def start(opts \\ []), do: :ets.new(__MODULE__, [:named_table] ++ opts)

  def store(key, value, ttl) do
    expires_at = ttl + timestamp()

    :ets.insert(__MODULE__, {key, value, expires_at})
  end

  def get(key) do
    case :ets.lookup(__MODULE__, key) do
      [{_key, value, expires_at}] -> {value, expires_at}
      [] -> :nocache
    end
  end

  def delete(key), do: :ets.delete(__MODULE__, key)

  def timestamp(), do: :erlang.monotonic_time(:millisecond)
end
