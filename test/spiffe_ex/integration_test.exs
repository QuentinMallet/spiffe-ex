defmodule SpiffeEx.IntegrationTest do
  use ExUnit.Case, async: false

  test "full authenticate flow: start_link succeeds and fetch_svid returns SVID" do
    {:ok, pid} =
      SpiffeEx.start_link(
        name: :integration_test_instance,
        workload_api_mod: SpiffeEx.MockWorkloadAPI,
        socket_path: "/tmp/test.sock",
        audience: ["integration-test"],
        client_id: "test-client",
        # Short retry policy so authenticate() fails fast without OIDC provider
        retry_policy: [max: 1, base_ms: 1]
      )

    assert is_pid(pid)
    assert Process.alive?(pid)

    # SvidCache is backed by MockWorkloadAPI — fetch_svid should succeed
    assert {:ok, svid} = SpiffeEx.fetch_svid(:integration_test_instance)
    assert svid.spiffe_id == "spiffe://example.org/test"
    assert DateTime.compare(svid.expires_at, DateTime.utc_now()) == :gt

    # authenticate() goes through OidcClient — without a real provider it returns error
    # Verify it returns a structured error rather than crashing
    result = SpiffeEx.authenticate(:integration_test_instance)
    assert {:error, _reason} = result
  after
    if pid = Process.whereis(:integration_test_instance), do: Supervisor.stop(pid)
  end
end
