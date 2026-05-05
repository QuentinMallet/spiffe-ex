defmodule SpiffeEx.WorkloadAPI do
  @callback fetch_jwt_svid(endpoint :: String.t(), audience :: [String.t()], grpc_opts :: keyword()) ::
              {:ok, SpiffeEx.SVID.t()} | {:error, atom()}
end
