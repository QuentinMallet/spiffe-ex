defmodule SpiffeEx.WorkloadAPI do
  @callback fetch_jwt_svid(socket_path :: String.t(), audience :: [String.t()]) ::
              {:ok, SpiffeEx.SVID.t()} | {:error, atom()}
end
