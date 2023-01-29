defmodule Cache.FunctionsRegistry do
  @moduledoc """
  Utility module for function registry.
  """

  @type fun :: (() -> {:ok, any} | {:error, any})

  @opts Application.compile_env!(__MODULE__, :ets_opts)
  @name Application.compile_env!(__MODULE__, :name)

  @spec start() :: atom
  def start() do
    :ets.new(@name, @opts)
  end

  @doc """
  Registers new function under specified `key`, saving function's `ttl` alongside, and returns
  :ok.  If some function is already registered under given `key`, gives up and returns
  {:error, :already_registered}.
  """
  @spec register(
          key :: any,
          fun :: fun(),
          ttl :: non_neg_integer
        ) :: :ok | {:error, :already_registered}
  def register(key, fun, ttl) do
    entry = {key, fun, ttl}

    case :ets.insert_new(@name, entry) do
      false -> {:error, :already_registered}
      true -> :ok
    end
  end

  @doc """
  Retrieves a function and associated `ttl` in {:ok, {function, ttl}} tuple using given `key`. If
  no entry with such value found returns {:error. :not_registered}.
  """
  @spec get(key :: any) :: {:ok, {fun(), non_neg_integer}}
  def get(key) do
    case :ets.lookup(@name, key) do
      [] -> {:error, :not_registered}
      [{_key, fun, ttl}] -> {:ok, {fun, ttl}}
    end
  end

  @doc """
  Retrieves function associated with given `key` and returns {:ok, function}. If no entry with
  such value found returns {:error. :not_registered}.
  """
  @spec get_fun(key :: any) :: {:ok, fun()} | {:error, :not_registered}
  def get_fun(key) do
    case :ets.match(@name, {key, :"$1", :_}) do
      [] -> {:error, :not_registered}
      [[fun]] -> {:ok, fun}
    end
  end

  @doc """
  Retrieves a function's `ttl` associated with given `key` and returns {:ok, ttl}. If no entry
  with such value found returns {:error. :not_registered}.
  """
  @spec get_ttl(key :: any) :: {:ok, non_neg_integer} | {:error, :not_registered}
  def get_ttl(key) do
    case :ets.match(@name, {key, :_, :"$1"}) do
      [] -> {:error, :not_registered}
      [[ttl]] -> {:ok, ttl}
    end
  end
end
