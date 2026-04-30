defmodule SpiffeEx.SvidCacheResilienceTest do
  use ExUnit.Case, async: false

  setup do
    start_supervised!({Registry, keys: :unique, name: SpiffeEx.Registry})
    name = :"svid_resilience_#{System.unique_integer([:positive])}"
    {:ok, name: name}
  end

  defp svid_cache_opts(name) do
    [
      name: name,
      socket_path: "/tmp/test.sock",
      workload_api_mod: SpiffeEx.MockWorkloadAPI,
      audience: ["test"],
      refresh_buffer_secs: 5
    ]
  end

  @tag :resilience
  test "SvidCache restarts and resumes after crash", %{name: name} do
    # Start a dedicated supervisor so SvidCache is restarted on crash
    {:ok, test_sup} =
      Supervisor.start_link([{SpiffeEx.SvidCache, svid_cache_opts(name)}],
        strategy: :one_for_one
      )

    try do
      # Verify it serves requests before crash
      assert {:ok, svid_before} = SpiffeEx.SvidCache.get(name)
      assert is_binary(svid_before.token)

      # Find and kill the GenServer
      [{pid, _}] = Registry.lookup(SpiffeEx.Registry, {name, :svid_cache})
      ref = Process.monitor(pid)
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^ref, :process, ^pid, :killed}, 1000

      # The supervisor restarts the child; poll until it responds
      assert wait_until(fn -> match?({:ok, _}, SpiffeEx.SvidCache.get(name)) end, 2000),
             "SvidCache did not recover within 2 seconds after crash"

      assert {:ok, svid_after} = SpiffeEx.SvidCache.get(name)
      assert is_binary(svid_after.token)
    after
      Supervisor.stop(test_sup)
    end
  end

  @tag :resilience
  test "no caller receives expired SVID under expiry pressure", %{name: name} do
    {:ok, test_sup} =
      Supervisor.start_link([{SpiffeEx.SvidCache, svid_cache_opts(name)}],
        strategy: :one_for_one
      )

    try do
      Process.sleep(30)

      tasks = Enum.map(1..10, fn _ -> Task.async(fn -> SpiffeEx.SvidCache.get(name) end) end)
      results = Enum.map(tasks, &Task.await(&1, 5000))

      for {:ok, svid} <- results do
        assert DateTime.compare(svid.expires_at, DateTime.utc_now()) == :gt,
               "Caller received an already-expired SVID"
      end
    after
      Supervisor.stop(test_sup)
    end
  end

  defp wait_until(fun, timeout_ms, interval_ms \\ 50) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms

    Enum.reduce_while(Stream.repeatedly(fn -> :tick end), false, fn _, _acc ->
      # Catch exits that occur when the process is temporarily dead during restart
      result =
        try do
          fun.()
        catch
          :exit, _ -> false
        end

      if result do
        {:halt, true}
      else
        if System.monotonic_time(:millisecond) < deadline do
          Process.sleep(interval_ms)
          {:cont, false}
        else
          {:halt, false}
        end
      end
    end)
  end
end
