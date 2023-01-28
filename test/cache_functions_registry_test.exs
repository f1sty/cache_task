defmodule Cache.FunctionsRegistryTest do
  use ExUnit.Case, async: true

  alias Cache.FunctionsRegistry, as: FR

  setup do
    Application.stop(:cache)
    FR.start()
    on_exit(fn -> Application.ensure_all_started(:cache) end)
  end

  test "register/3 returns :ok if function was registered" do
    assert FR.register("function", fn -> {:ok, 3.14} end, 1000) == :ok
  end

  test "register/3 returns {:error, already_registered} if function already registered" do
    assert FR.register("function", fn -> {:ok, 3.14} end, 1000) == :ok
    assert FR.register("function", fn -> {:ok, 3.14} end, 1000) == {:error, :already_registered}
  end

  test "get/1 returns {:ok, {fun, ttl}} for registered function" do
    fun = fn -> {:ok, "torrents"} end

    assert FR.register("function", fun, 1000) == :ok
    assert {:ok, {^fun, 1000}} = FR.get("function")
  end

  test "get/1 returns {:error, :not_registered} for not registered function" do
    assert FR.get("function") == {:error, :not_registered}
  end
end
