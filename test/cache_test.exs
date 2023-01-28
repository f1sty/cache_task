defmodule CacheTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog

  alias Cache.Store

  describe "register_function/4" do
    setup do
      {:ok, context()}
    end

    test "returns `:ok` with before unregistered function that returns `{:ok, result}`",
         %{
           constant_function: function,
           ttl: ttl,
           refresh_interval: refresh_interval,
           key: key
         } do
      assert Cache.register_function(function, key, ttl, refresh_interval) == :ok
    end

    test "returns `:ok` with before unregistered function that returns `{:error, reason}`",
         %{
           error_function: function,
           ttl: ttl,
           refresh_interval: refresh_interval,
           key: key
         } do
      assert Cache.register_function(function, key, ttl, refresh_interval) == :ok
    end

    test "return `{:error, :already_registered}` if function already registered", %{
      constant_function: function,
      ttl: ttl,
      refresh_interval: refresh_interval,
      key: key
    } do
      assert Cache.register_function(function, key, ttl, refresh_interval) == :ok

      assert Cache.register_function(function, key, ttl, refresh_interval) ==
               {:error, :already_registered}
    end

    test "cache result if registered function returned `{:ok, result}`", %{
      constant_function: function,
      ttl: ttl,
      refresh_interval: refresh_interval,
      key: key
    } do
      assert Cache.register_function(function, key, ttl, refresh_interval) == :ok
      Process.sleep(10)
      assert {:ok, 42} = Cache.get(key)
    end

    test "doesn't cache result if registered function returned `{:error, reason}`", %{
      error_function: function,
      ttl: ttl,
      refresh_interval: refresh_interval,
      key: key
    } do
      assert Cache.register_function(function, key, ttl, refresh_interval) == :ok
      assert Store.get(key) == :nocache
    end

    test "results' cache rehydrates after `refresh_interval` milliseconds passed", %{
      changing_function: function,
      ttl: ttl,
      key: key
    } do
      refresh_interval = 100

      assert Cache.register_function(function, key, ttl, refresh_interval) == :ok

      refresh_interval |> div(2) |> Process.sleep()
      {:ok, first_result} = Cache.get(key)

      refresh_interval |> div(2) |> Process.sleep()
      {:ok, second_result} = Cache.get(key)

      refute first_result === second_result
    end

    test "results' cache doesn't rehydrates before `refresh_interval` milliseconds passed", %{
      changing_function: function,
      ttl: ttl,
      key: key
    } do
      refresh_interval = 100

      assert Cache.register_function(function, key, ttl, refresh_interval) == :ok

      refresh_interval |> div(2) |> Process.sleep()
      {:ok, first_result} = Cache.get(key)

      refresh_interval |> div(3) |> Process.sleep()
      {:ok, second_result} = Cache.get(key)

      assert first_result === second_result
    end

    test "results' cache removed after `ttl` milliseconds passed without successful refresh", %{
      error_function: function,
      key: key
    } do
      ttl = 220
      refresh_interval = 100

      assert Cache.register_function(function, key, ttl, refresh_interval) == :ok

      Process.sleep(ttl)

      assert Store.get(key) == :nocache
    end

    test "return `:ok` even if task raised and error", %{
      raising_function: function,
      ttl: ttl,
      refresh_interval: refresh_interval,
      key: key
    } do
      assert Cache.register_function(function, key, ttl, refresh_interval) == :ok
    end

    test "doesn't save cache if task raised and error", %{
      raising_function: function,
      ttl: ttl,
      refresh_interval: refresh_interval,
      key: key
    } do
      assert Cache.register_function(function, key, ttl, refresh_interval) == :ok
      assert Store.get(key) == :nocache
    end

    test "logs error raised by task", %{
      raising_function: function,
      ttl: ttl,
      refresh_interval: refresh_interval,
      key: key
    } do
      {result, log} =
        with_log(fn ->
          Cache.register_function(function, key, ttl, refresh_interval)
        end)

      assert :ok = result
      assert log =~ "exited abnormally with: ohshi~"

      assert Store.get(key) == :nocache
    end
  end

  describe "get/1" do
    setup do
      {:ok, context()}
    end

    test "returns `{:error, :not_registered}` when function is not registered wit given key", %{
      key: key
    } do
      assert Cache.get(key) == {:error, :not_registered}
    end

    test "returns `{:error, :timeout}` if no result was returned after `timeout` milliseconds", %{
      longrunning_function: function,
      ttl: ttl,
      refresh_interval: refresh_interval,
      key: key
    } do
      assert Cache.register_function(function, key, ttl, refresh_interval) == :ok
      assert Cache.get(key, 10) == {:error, :timeout}
    end

    test "returns `{:ok, result}` if result was returned during `timeout` milliseconds", %{
      longrunning_function: function,
      ttl: ttl,
      refresh_interval: refresh_interval,
      key: key
    } do
      assert Cache.register_function(function, key, ttl, refresh_interval) == :ok
      assert Cache.get(key, 10) == {:error, :timeout}

      Process.sleep(190)

      assert Cache.get(key) == {:ok, 1991}
    end
  end

  defp context() do
    constant_function = fn -> {:ok, 42} end
    error_function = fn -> {:error, "too lazy to run"} end
    changing_function = fn -> {:ok, :erlang.monotonic_time(:millisecond)} end
    raising_function = fn -> raise "ohshi~" end

    longrunning_function = fn ->
      Process.sleep(200)
      {:ok, 1991}
    end

    key = "function" <> to_string(:erlang.monotonic_time())

    %{
      changing_function: changing_function,
      error_function: error_function,
      constant_function: constant_function,
      longrunning_function: longrunning_function,
      raising_function: raising_function,
      ttl: 6000,
      refresh_interval: 1000,
      key: key
    }
  end
end
