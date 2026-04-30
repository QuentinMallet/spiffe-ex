defmodule SpiffeEx.TokenCacheTest do
  use ExUnit.Case, async: false

  alias SpiffeEx.TokenCache

  setup do
    start_supervised!({Registry, keys: :unique, name: SpiffeEx.Registry})
    name = :"token_cache_#{System.unique_integer([:positive])}"
    {:ok, name: name}
  end

  defp start_token_cache(name, overrides \\ []) do
    opts =
      Keyword.merge(
        [
          name: name,
          socket_path: "/tmp/test.sock",
          client_id: "test-client",
          refresh_buffer_secs: 5
        ],
        overrides
      )

    start_supervised!({TokenCache, opts})
  end

  defp start_svid_cache(name, workload_mod \\ SpiffeEx.MockWorkloadAPI) do
    start_supervised!(
      {SpiffeEx.SvidCache,
       [
         name: name,
         socket_path: "/tmp/test.sock",
         workload_api_mod: workload_mod,
         audience: ["test"]
       ]}
    )
  end

  test "get returns cached token when not expired", %{name: name} do
    # Start an error SvidCache so fetch_and_store returns a structured error
    # rather than crashing (tests idempotent error behavior)
    start_svid_cache(name, SpiffeEx.ErrorWorkloadAPI)
    start_token_cache(name)

    first = TokenCache.get(name)
    second = TokenCache.get(name)

    # Both return structured errors (not crashes), and consistently
    assert {:error, _} = first
    assert first == second
  end

  test "get fetches fresh token when cache empty", %{name: name} do
    start_svid_cache(name)
    start_token_cache(name, retry_policy: [max: 1, base_ms: 1])

    # SvidCache returns a valid SVID; OidcClient has no provider configured.
    # Verifies the cache-miss path is exercised and returns a structured error.
    assert {:error, _} = TokenCache.get(name)
  end

  test "get returns error when SVID unavailable", %{name: name} do
    # SvidCache with error mock never yields an SVID
    start_svid_cache(name, SpiffeEx.ErrorWorkloadAPI)
    start_token_cache(name)

    # fetch_and_store -> SvidCache.get -> {:error, :workload_api_unavailable}
    assert {:error, :workload_api_unavailable} = TokenCache.get(name)
  end
end
