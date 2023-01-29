defmodule Cache.Store do
  @moduledoc """
  Utility module for cache store.
  """

  @opts Application.compile_env!(__MODULE__, :ets_opts)
  @name Application.compile_env!(__MODULE__, :name)

  @spec start() :: atom
  def start() do
    :ets.new(@name, @opts)
  end

  @doc """
  Stores value under the given `key`, with value's expiration timestamp. Always returns `true`, or
  raises.
  """
  @spec store(
          key :: any,
          value :: {:ok, any},
          ttl :: non_neg_integer
        ) :: true
  def store(key, value, ttl) do
    expires_at = ttl + timestamp()

    :ets.insert(@name, {key, value, expires_at})
  end

  @doc """
  Retrieves value and expiration date from cache using given key, returns {value, expires_at}. If
  value is not cached, returns :nocache.
  """
  @spec get(key :: any) :: {any, integer} | :nocache
  def get(key) do
    case :ets.lookup(@name, key) do
      [] -> :nocache
      [{_key, value, expires_at}] -> {value, expires_at}
    end
  end

  @doc """
  Removes value and expiration date from cache. Always returns `true` or raises.
  """
  @spec delete(key :: any) :: true
  def delete(key), do: :ets.delete(@name, key)

  defp timestamp(), do: :erlang.monotonic_time(:millisecond)
end
