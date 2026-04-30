defmodule SpiffeEx.WorkloadAPI.GrpcAdapter do
  @behaviour SpiffeEx.WorkloadAPI

  alias SpiffeEx.Proto.Workload.{JWTSVIDRequest, SpiffeWorkloadAPI}

  @impl true
  def fetch_jwt_svid(socket_path, audience) do
    start = System.monotonic_time(:millisecond)

    case GRPC.Stub.connect("unix:#{socket_path}", []) do
      {:ok, channel} ->
        request = %JWTSVIDRequest{audience: audience, spiffe_id: ""}
        do_fetch(channel, request, start)

      {:error, _reason} ->
        {:error, :workload_api_unavailable}
    end
  end

  defp do_fetch(channel, request, start) do
    case SpiffeWorkloadAPI.Stub.fetch_jwtsvid(channel, request) do
      {:ok, %{svids: [%{svid: jwt, spiffe_id: spiffe_id} | _]}} ->
        with {:ok, expires_at} <- parse_expiry(jwt) do
          duration = System.monotonic_time(:millisecond) - start

          :telemetry.execute(
            [:spiffe_ex, :svid, :fetch],
            %{duration: duration},
            %{spiffe_id: spiffe_id}
          )

          {:ok, %SpiffeEx.SVID{token: jwt, spiffe_id: spiffe_id, expires_at: expires_at}}
        end

      {:ok, %{svids: []}} ->
        {:error, :workload_api_unavailable}

      {:error, _reason} ->
        {:error, :workload_api_unavailable}
    end
  end

  defp parse_expiry(jwt) do
    try do
      %{"exp" => exp} = JOSE.JWT.peek_payload(jwt).fields

      exp_int =
        cond do
          is_integer(exp) -> exp
          is_float(exp) -> trunc(exp)
          is_binary(exp) -> String.to_integer(exp)
        end

      {:ok, DateTime.from_unix!(exp_int)}
    rescue
      _ -> {:error, :workload_api_unavailable}
    end
  end
end
