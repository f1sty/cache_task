defmodule Cache do
  use GenServer

  require Logger

  alias Cache.{Store, FunctionsRegistry, TasksSupersisor}

  @type result ::
          {:ok, any()}
          | {:error, :timeout}
          | {:error, :not_registered}

  def start_link(opts \\ [:set, :public]) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    FunctionsRegistry.start()

    cache = Store.new(opts)
    state = %{cache: cache, running_tasks: %{}}

    {:ok, state}
  end

  @impl true
  def handle_call(
        {:register_function, fun, key, ttl, refresh_interval},
        _from,
        %{running_tasks: tasks} = state
      ) do
    case FunctionsRegistry.register(key, fun, ttl) do
      {:error, :already_registered} = error ->
        {:reply, error, state}

      :ok ->
        tasks = run_task(key, tasks)
        state = %{state | running_tasks: tasks}

        schedule_refresh_results(key, refresh_interval)
        schedule_maybe_discard(key, ttl)

        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:get, key, timeout}, _from, %{cache: cache, running_tasks: tasks} = state) do
    case Store.get(cache, key) do
      [{^key, result, _ttl}] ->
        {:reply, result, state}

      [] ->
        task = Map.get(tasks, key)

        result =
          case Task.yield(task, timeout) do
            nil ->
              {:error, :timeout}

            {:ok, result} ->
              case FunctionsRegistry.get(key) do
                {:error, _} = error ->
                  error

                {:ok, [_fun, ttl]} ->
                  Store.store(cache, key, result, ttl)

                  result
              end
          end

        {:reply, result, state}
    end
  end

  @impl true
  def handle_info({:refresh_result, key, refresh_interval}, %{running_tasks: tasks} = state) do
    tasks = run_task(key, tasks)
    state = %{state | running_tasks: tasks}

    schedule_refresh_results(key, refresh_interval)

    {:noreply, state}
  end

  @impl true
  def handle_info({:maybe_discard, key, ttl}, %{cache: cache} = state) do
    [{_key, _result, expires_at}] = Store.get(cache, key)
    if Store.timestamp() > expires_at, do: Store.delete(cache, key)

    schedule_maybe_discard(key, ttl)

    {:noreply, state}
  end

  @impl true
  def handle_info({task_ref, {:ok, result}}, %{cache: cache, running_tasks: tasks} = state) do
    key = Enum.find_value(tasks, fn {key, task} -> task.ref == task_ref and key end)
    {:ok, [_fun, ttl]} = FunctionsRegistry.get(key)

    Store.store(cache, key, result, ttl)

    {:noreply, state}
  end

  @impl true
  def handle_info({_task_ref, {:error, _reason}}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, task_ref, :process, _pid, :normal}, %{running_tasks: tasks} = state) do
    key = Enum.find_value(tasks, fn {key, task} -> task.ref == task_ref and key end)
    tasks = Map.delete(tasks, key)
    state = %{state | running_tasks: tasks}

    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, task_ref, :process, _pid, {reason, _}}, %{running_tasks: tasks} = state) do
    Logger.error("Task #{inspect(task_ref)} exited abnormally with #{inspect(reason)}")
    key = Enum.find_value(tasks, fn {key, task} -> task.ref == task_ref and key end)
    tasks = Map.delete(tasks, key)
    state = %{state | running_tasks: tasks}

    {:noreply, state}
  end

  @doc ~s"""
  Registers a function that will be computed periodically to update the cache.

  Arguments:
    - `fun`: a 0-arity function that computes the value and returns either
      `{:ok, value}` or `{:error, reason}`.
    - `key`: associated with the function and is used to retrieve the stored
    value.
    - `ttl` ("time to live"): how long (in milliseconds) the value is stored
      before it is discarded if the value is not refreshed.
    - `refresh_interval`: how often (in milliseconds) the function is
      recomputed and the new value stored. `refresh_interval` must be strictly
      smaller than `ttl`. After the value is refreshed, the `ttl` counter is
      restarted.

  The value is stored only if `{:ok, value}` is returned by `fun`. If `{:error,
  reason}` is returned, the value is not stored and `fun` must be retried on
  the next run.
  """
  @spec register_function(
          fun :: (() -> {:ok, any()} | {:error, any()}),
          key :: any,
          ttl :: non_neg_integer(),
          refresh_interval :: non_neg_integer()
        ) :: :ok | {:error, :already_registered}
  def register_function(fun, key, ttl, refresh_interval)
      when is_function(fun, 0) and is_integer(ttl) and ttl > 0 and
             is_integer(refresh_interval) and
             refresh_interval < ttl do
    GenServer.call(__MODULE__, {:register_function, fun, key, ttl, refresh_interval})
  end

  @doc ~s"""
  Get the value associated with `key`.

  Details:
    - If the value for `key` is stored in the cache, the value is returned
      immediately.
    - If a recomputation of the function is in progress, the last stored value
      is returned.
    - If the value for `key` is not stored in the cache but a computation of
      the function associated with this `key` is in progress, wait up to
      `timeout` milliseconds. If the value is computed within this interval,
      the value is returned. If the computation does not finish in this
      interval, `{:error, :timeout}` is returned.
    - If `key` is not associated with any function, return `{:error,
      :not_registered}`
  """
  @spec get(any(), non_neg_integer(), Keyword.t()) :: result
  def get(key, timeout \\ 30_000, _opts \\ []) when is_integer(timeout) and timeout > 0 do
    GenServer.call(__MODULE__, {:get, key, timeout}, :infinity)
  end

  defp run_task(key, tasks) do
    {:ok, [fun, _ttl]} = FunctionsRegistry.get(key)
    task = Task.Supervisor.async_nolink(TasksSupersisor, fun, timeout: :infinity)

    Map.put(tasks, key, task)
  end

  defp schedule_maybe_discard(key, ttl) do
    :erlang.send_after(ttl, self(), {:maybe_discard, key, ttl})
  end

  defp schedule_refresh_results(key, refresh_interval) do
    :erlang.send_after(refresh_interval, self(), {:refresh_result, key, refresh_interval})
  end
end
