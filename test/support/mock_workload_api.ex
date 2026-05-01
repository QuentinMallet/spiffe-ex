defmodule SpiffeEx.MockWorkloadAPI do
  @behaviour SpiffeEx.WorkloadAPI

  @impl true
  def fetch_jwt_svid(_endpoint, audience, _grpc_opts) do
    expires_at = DateTime.add(DateTime.utc_now(), 300, :second)
    exp = DateTime.to_unix(expires_at)

    aud_json =
      case audience do
        [] -> "[]"
        list -> "[" <> Enum.map_join(list, ",", fn a -> ~s("#{a}") end) <> "]"
      end

    header = Base.url_encode64(~s({"alg":"HS256","typ":"JWT"}), padding: false)

    payload =
      Base.url_encode64(
        ~s({"sub":"spiffe://example.org/test","aud":#{aud_json},"exp":#{exp},"iss":"spiffe://example.org"}),
        padding: false
      )

    jwt = "#{header}.#{payload}.test-sig"

    {:ok,
     %SpiffeEx.SVID{
       token: jwt,
       spiffe_id: "spiffe://example.org/test",
       expires_at: expires_at
     }}
  end
end

defmodule SpiffeEx.ErrorWorkloadAPI do
  @behaviour SpiffeEx.WorkloadAPI

  @impl true
  def fetch_jwt_svid(_endpoint, _audience, _grpc_opts) do
    {:error, :unavailable}
  end
end
