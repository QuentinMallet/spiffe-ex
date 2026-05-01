defmodule SpiffeEx.SvidCachePropertiesTest do
  use ExUnit.Case, async: false
  use ExUnitProperties

  import SpiffeEx.Generators

  setup do
    start_supervised!({Registry, keys: :unique, name: SpiffeEx.Registry})
    :ok
  end

  property "get always returns non-expired SVID for any refresh buffer" do
    check all(buffer <- refresh_buffer_seconds()) do
      name = :"svid_prop_#{System.unique_integer([:positive])}"

      # Use GenServer.start_link directly to avoid child-ID conflicts across iterations
      {:ok, pid} =
        SpiffeEx.SvidCache.start_link(
          name: name,
          endpoint: "unix:/tmp/test.sock",
          workload_api_mod: SpiffeEx.MockWorkloadAPI,
          audience: [],
          refresh_buffer_secs: buffer
        )

      try do
        # MockWorkloadAPI returns SVIDs expiring in 300 seconds.
        # Invariant: regardless of refresh buffer, returned SVID is never expired.
        assert {:ok, svid} = SpiffeEx.SvidCache.get(name)
        assert DateTime.compare(svid.expires_at, DateTime.utc_now()) == :gt
      after
        GenServer.stop(pid, :normal, 1000)
      end
    end
  end

  property "concurrent get calls return consistent SVID token" do
    check all(n <- concurrent_caller_count()) do
      name = :"svid_concurrent_#{System.unique_integer([:positive])}"

      {:ok, pid} =
        SpiffeEx.SvidCache.start_link(
          name: name,
          endpoint: "unix:/tmp/test.sock",
          workload_api_mod: SpiffeEx.MockWorkloadAPI,
          audience: ["test"],
          refresh_buffer_secs: 10
        )

      try do
        # Let the proactive refresh populate the cache
        Process.sleep(30)

        tasks = Enum.map(1..n, fn _ -> Task.async(fn -> SpiffeEx.SvidCache.get(name) end) end)
        results = Enum.map(tasks, &Task.await(&1, 5000))

        ok_results = Enum.filter(results, &match?({:ok, _}, &1))

        unless Enum.empty?(ok_results) do
          tokens = Enum.map(ok_results, fn {:ok, svid} -> svid.token end)
          # All concurrent callers must see the same token (cache consistency)
          assert length(Enum.uniq(tokens)) == 1
        end
      after
        GenServer.stop(pid, :normal, 1000)
      end
    end
  end
end
