defmodule SpiffeEx.SvidCacheTest do
  use ExUnit.Case, async: false

  alias SpiffeEx.SvidCache

  setup do
    start_supervised!({Registry, keys: :unique, name: SpiffeEx.Registry})
    name = :"svid_cache_#{System.unique_integer([:positive])}"
    {:ok, name: name}
  end

  defp start_cache(name, overrides \\ []) do
    opts =
      Keyword.merge(
        [
          name: name,
          socket_path: "/tmp/test.sock",
          workload_api_mod: SpiffeEx.MockWorkloadAPI,
          audience: ["test"],
          refresh_buffer_secs: 10
        ],
        overrides
      )

    start_supervised!({SvidCache, opts})
  end

  test "get fetches fresh SVID when cache empty", %{name: name} do
    start_cache(name)
    # get/1 falls through to GenServer.call which fetches on demand
    assert {:ok, svid} = SvidCache.get(name)
    assert is_binary(svid.token)
    assert svid.spiffe_id == "spiffe://example.org/test"
  end

  test "get returns cached SVID when not expired", %{name: name} do
    start_cache(name)
    # Let the proactive refresh populate ETS
    Process.sleep(50)
    assert {:ok, svid} = SvidCache.get(name)
    assert DateTime.compare(svid.expires_at, DateTime.utc_now()) == :gt
  end

  test "get returns error when workload API unavailable", %{name: name} do
    start_cache(name, workload_api_mod: SpiffeEx.ErrorWorkloadAPI)
    assert {:error, :workload_api_unavailable} = SvidCache.get(name)
  end

  test "cache schedules refresh before expiry", %{name: name} do
    start_cache(name)
    # After init, refresh is scheduled; verify SVID is populated
    Process.sleep(50)
    assert {:ok, svid} = SvidCache.get(name)
    # expires_at is in the future — proactive refresh is scheduled before it
    assert DateTime.compare(svid.expires_at, DateTime.utc_now()) == :gt
  end

  test "multiple concurrent get calls return consistent result", %{name: name} do
    start_cache(name)
    Process.sleep(50)

    results =
      1..10
      |> Enum.map(fn _ -> Task.async(fn -> SvidCache.get(name) end) end)
      |> Enum.map(&Task.await/1)

    assert Enum.all?(results, &match?({:ok, _}, &1))
    tokens = Enum.map(results, fn {:ok, svid} -> svid.token end)
    # All concurrent callers get the same cached token
    assert length(Enum.uniq(tokens)) == 1
  end
end
