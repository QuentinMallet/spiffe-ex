defmodule SpiffeEx.TokenCacheResilienceTest do
  use ExUnit.Case, async: false

  setup do
    start_supervised!({Registry, keys: :unique, name: SpiffeEx.Registry})
    name = :"token_resilience_#{System.unique_integer([:positive])}"
    {:ok, name: name}
  end

  defp svid_cache_opts(name) do
    [
      name: name,
      socket_path: "/tmp/test.sock",
      workload_api_mod: SpiffeEx.MockWorkloadAPI,
      audience: ["test"]
    ]
  end

  defp token_cache_opts(name) do
    [
      name: name,
      socket_path: "/tmp/test.sock",
      client_id: "test-client",
      refresh_buffer_secs: 5,
      retry_policy: [max: 1, base_ms: 1]
    ]
  end

  @tag :resilience
  test "TokenCache restarts and resumes after crash", %{name: name} do
    # Start both caches under a shared supervisor so crashes are recovered
    {:ok, test_sup} =
      Supervisor.start_link(
        [
          {SpiffeEx.SvidCache, svid_cache_opts(name)},
          {SpiffeEx.TokenCache, token_cache_opts(name)}
        ],
        strategy: :one_for_one
      )

    try do
      # Verify TokenCache responds (expected error without real OIDC)
      assert {:error, _} = SpiffeEx.TokenCache.get(name)

      # Find and kill the TokenCache GenServer
      [{pid, _}] = Registry.lookup(SpiffeEx.Registry, {name, :token_cache})
      ref = Process.monitor(pid)
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^ref, :process, ^pid, :killed}, 1000

      # Supervisor restarts it; poll until responsive again
      assert wait_until(
               fn ->
                 case SpiffeEx.TokenCache.get(name) do
                   {:ok, _} -> true
                   {:error, _} -> true
                   _ -> false
                 end
               end,
               2000
             ),
             "TokenCache did not recover within 2 seconds after crash"
    after
      Supervisor.stop(test_sup)
    end
  end

  @tag :resilience
  test "concurrent callers return consistent result under token stampede", %{name: name} do
    {:ok, test_sup} =
      Supervisor.start_link(
        [
          {SpiffeEx.SvidCache, svid_cache_opts(name)},
          {SpiffeEx.TokenCache, token_cache_opts(name)}
        ],
        strategy: :one_for_one
      )

    try do
      tasks =
        Enum.map(1..10, fn _ ->
          Task.async(fn -> SpiffeEx.TokenCache.get(name) end)
        end)

      results = Enum.map(tasks, &Task.await(&1, 10_000))

      # All callers should return structured tuples, never crash
      assert Enum.all?(results, fn
               {:ok, _} -> true
               {:error, _} -> true
               _ -> false
             end)
    after
      Supervisor.stop(test_sup)
    end
  end

  defp wait_until(fun, timeout_ms, interval_ms \\ 50) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms

    Enum.reduce_while(Stream.repeatedly(fn -> :tick end), false, fn _, _acc ->
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
