defmodule Cache do
  @moduledoc """
  Implements self-rehydrating memoization cache on top of `GenServer`
  """

  use GenServer

  require Logger

  alias Cache.{Store, FunctionsRegistry, TasksSupervisor}

  @type result ::
          {:ok, any()}
          | {:error, :timeout}
          | {:error, :not_registered}

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, opts)
  end

  @impl true
  def init(initial_state) do
    FunctionsRegistry.start()
    Store.start()

    {:ok, initial_state}
  end

  @impl true
  def handle_call({:register_function, fun, key, ttl, refresh_interval}, _from, state) do
    case FunctionsRegistry.register(key, fun, ttl) do
      {:error, :already_registered} = error ->
        {:reply, error, state}

      :ok ->
        state = start_task(state, key)

        schedule_refresh_result(key, refresh_interval)
        schedule_maybe_discard(key, ttl)

        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:get, key, timeout}, _from, state) do
    result =
      with :nocache <- Store.get(key),
           {:ok, ttl} <- FunctionsRegistry.get_ttl(key),
           %Task{} = task <- Map.get(state, key, {:error, :notask}),
           {:ok, result} <- Task.yield(task, timeout) do
        Store.store(key, result, ttl)
        result
      else
        nil -> {:error, :timeout}
        {:error, reason} -> {:error, reason}
        {result, _ttl} -> result
      end

    {:reply, result, state}
  end

  @impl true
  def handle_info({:refresh_result, key, refresh_interval}, state) do
    state = start_task(state, key)
    schedule_refresh_result(key, refresh_interval)

    {:noreply, state}
  end

  @impl true
  def handle_info({:maybe_discard, key, ttl}, state) do
    with {_result, expires_at} <- Store.get(key) do
      Store.timestamp() >= expires_at && Store.delete(key)
    else
      :nocache ->
        Logger.debug("Tried to discard #{key} with running tasks: #{inspect(state)}, ignoring")
    end

    schedule_maybe_discard(key, ttl)

    {:noreply, state}
  end

  @impl true
  def handle_info({task_ref, {:ok, _} = result}, state) do
    key = Enum.find_value(state, fn {key, task} -> task.ref == task_ref && key end)
    {:ok, ttl} = FunctionsRegistry.get_ttl(key)

    Store.store(key, result, ttl)

    {:noreply, state}
  end

  @impl true
  def handle_info({task_ref, {:error, reason}}, state) do
    Logger.debug("Task #{inspect(task_ref)} returned error with reason: #{reason}, ignoring")
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, task_ref, :process, _pid, :normal}, state) do
    {:noreply, remove_task(state, task_ref)}
  end

  @impl true
  def handle_info({:DOWN, task_ref, :process, _pid, {reason, _}}, state) do
    Logger.error("Task #{inspect(task_ref)} exited abnormally with: #{Exception.message(reason)}")

    {:noreply, remove_task(state, task_ref)}
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

  @doc ~s"""
  Starts a task under the task supervisor. Task is not linked, we don't wanna the whole system to
  go down because of failed task. A task is started only if:

    - there are no other tasks running associated with the same key
    - the function, that suppose to be run in task is registered

  After starting a task, it adds task data into the map using same key as a function being started.
  """
  @spec start_task(tasks :: map, key :: any) :: map
  def start_task(tasks, key) do
    with false <- Map.has_key?(tasks, key),
         {:ok, fun} <- FunctionsRegistry.get_fun(key),
         %Task{} = task <- Task.Supervisor.async_nolink(TasksSupervisor, fun, timeout: :infinity) do
      Map.put(tasks, key, task)
    else
      _ -> tasks
    end
  end

  defp remove_task(tasks, task_ref) do
    key = Enum.find_value(tasks, fn {key, task} -> task.ref == task_ref && key end)

    Map.delete(tasks, key)
  end

  defp schedule_maybe_discard(key, ttl) do
    :erlang.send_after(ttl, self(), {:maybe_discard, key, ttl})
  end

  defp schedule_refresh_result(key, refresh_interval) do
    :erlang.send_after(refresh_interval, self(), {:refresh_result, key, refresh_interval})
  end
end
