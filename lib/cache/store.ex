defmodule Cache.Store do
  def new(opts), do: :ets.new(Cache.Results, [:named_table] ++ opts)

  def store(store, key, value, ttl) do
    expires_at = ttl + timestamp()

    :ets.insert(store, {key, value, expires_at})
  end

  def get(store, key), do: :ets.lookup(store, key)

  def delete(store, key), do: :ets.delete(store, key)

  def timestamp(), do: :erlang.monotonic_time(:millisecond)
end
