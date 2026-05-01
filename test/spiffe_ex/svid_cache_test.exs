defmodule SpiffeEx.CapturingMock do
  @behaviour SpiffeEx.WorkloadAPI

  @impl true
  def fetch_jwt_svid(endpoint, audience, grpc_opts) do
    if pid = Process.whereis(:capturing_mock) do
      Agent.update(pid, fn _ -> %{endpoint: endpoint, audience: audience, grpc_opts: grpc_opts} end)
    end

    expires_at = DateTime.add(DateTime.utc_now(), 300, :second)

    {:ok,
     %SpiffeEx.SVID{
       token: "captured.jwt",
       spiffe_id: "spiffe://example.org/test",
       expires_at: expires_at
     }}
  end
end

defmodule SpiffeEx.SvidCacheTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

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
          endpoint: "unix:/tmp/test.sock",
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

  describe "endpoint and grpc_opts" do
    test "TCP endpoint is passed to workload adapter", %{name: name} do
      {:ok, agent} = Agent.start(fn -> %{} end, name: :capturing_mock)
      on_exit(fn -> Agent.stop(agent) end)

      start_cache(name,
        endpoint: "localhost:8080",
        workload_api_mod: SpiffeEx.CapturingMock
      )

      Process.sleep(50)
      captured = Agent.get(:capturing_mock, & &1)
      assert captured.endpoint == "localhost:8080"
    end

    test "unix endpoint is passed to workload adapter", %{name: name} do
      start_cache(name, endpoint: "unix:/tmp/agent.sock")
      assert {:ok, svid} = SvidCache.get(name)
      assert is_binary(svid.token)
    end

    test "deprecated socket_path logs warning and still works", %{name: name} do
      log =
        capture_log(fn ->
          start_supervised!({SvidCache,
           [
             name: name,
             socket_path: "/tmp/agent.sock",
             workload_api_mod: SpiffeEx.MockWorkloadAPI,
             audience: ["test"],
             refresh_buffer_secs: 10
           ]})
        end)

      assert log =~ ":socket_path"
      assert {:ok, svid} = SvidCache.get(name)
      assert is_binary(svid.token)
    end

    test "grpc_opts are passed to workload adapter", %{name: name} do
      {:ok, agent} = Agent.start(fn -> %{} end, name: :capturing_mock)
      on_exit(fn -> Agent.stop(agent) end)

      start_cache(name,
        endpoint: "localhost:8080",
        grpc_opts: [timeout: 5000],
        workload_api_mod: SpiffeEx.CapturingMock
      )

      Process.sleep(50)
      captured = Agent.get(:capturing_mock, & &1)
      assert captured.grpc_opts == [timeout: 5000]
    end
  end
end
