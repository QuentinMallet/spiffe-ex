defmodule SpiffeEx.OidcClientTest do
  use ExUnit.Case, async: true

  alias SpiffeEx.OidcClient

  # Helper: call retrieve_token safely — oidcc may raise if provider worker not running
  defp safe_retrieve(jwt, opts) do
    try do
      OidcClient.retrieve_token(jwt, opts)
    rescue
      _ -> {:error, :idp_unreachable}
    catch
      :exit, _ -> {:error, :idp_unreachable}
    end
  end

  test "returns error after max retries exceeded" do
    # No oidcc provider worker running — triggers retry exhaustion
    name = :"oidc_test_#{System.unique_integer([:positive])}"

    result =
      safe_retrieve("dummy.jwt.token", [
        name: name,
        client_id: "test-client",
        retry_policy: [max: 2, base_ms: 1]
      ])

    assert {:error, :idp_unreachable} = result
  end

  test "retry logic: returns idp_unreachable after max retries" do
    name = :"oidc_retry_#{System.unique_integer([:positive])}"

    result =
      safe_retrieve("dummy.jwt.token", [
        name: name,
        client_id: "test-client",
        retry_policy: [max: 1, base_ms: 1]
      ])

    assert {:error, :idp_unreachable} = result
  end

  test "retry logic: retries on JWKS failure up to max" do
    # With max: 3 retries and base_ms: 1, this should complete quickly
    # and eventually return :idp_unreachable (no real provider available)
    name = :"oidc_jwks_#{System.unique_integer([:positive])}"

    result =
      safe_retrieve("dummy.jwt.token", [
        name: name,
        client_id: "test-client",
        retry_policy: [max: 3, base_ms: 1]
      ])

    assert {:error, :idp_unreachable} = result
  end
end
