# Hand-written Elixir protobuf bindings for the SPIFFE Workload API.
# Generated from: proto/workload.proto
#
# To regenerate with protoc:
#   protoc --elixir_out=plugins=grpc:lib/spiffe_ex/proto -I proto proto/workload.proto

defmodule SpiffeEx.Proto.Workload.JWTSVIDRequest do
  use Protobuf, syntax: :proto3

  field(:audience, 1, repeated: true, type: :string)
  field(:spiffe_id, 2, type: :string)
end

defmodule SpiffeEx.Proto.Workload.JWTSVID do
  use Protobuf, syntax: :proto3

  field(:spiffe_id, 1, type: :string)
  field(:svid, 2, type: :string)
  field(:hint, 3, type: :int64)
end

defmodule SpiffeEx.Proto.Workload.JWTSVIDResponse do
  use Protobuf, syntax: :proto3

  field(:svids, 1, repeated: true, type: SpiffeEx.Proto.Workload.JWTSVID)
end

defmodule SpiffeEx.Proto.Workload.JWTBundlesRequest do
  use Protobuf, syntax: :proto3
end

defmodule SpiffeEx.Proto.Workload.JWTBundlesResponse.BundlesEntry do
  use Protobuf, map: true, syntax: :proto3

  field(:key, 1, type: :string)
  field(:value, 2, type: :bytes)
end

defmodule SpiffeEx.Proto.Workload.JWTBundlesResponse do
  use Protobuf, syntax: :proto3

  field(:bundles, 1,
    repeated: true,
    type: SpiffeEx.Proto.Workload.JWTBundlesResponse.BundlesEntry,
    map: true
  )
end

defmodule SpiffeEx.Proto.Workload.ValidateJWTSVIDRequest do
  use Protobuf, syntax: :proto3

  field(:audience, 1, type: :string)
  field(:svid, 2, type: :string)
end

defmodule SpiffeEx.Proto.Workload.ValidateJWTSVIDResponse do
  use Protobuf, syntax: :proto3

  field(:spiffe_id, 1, type: :string)
end

defmodule SpiffeEx.Proto.Workload.X509SVIDRequest do
  use Protobuf, syntax: :proto3
end

defmodule SpiffeEx.Proto.Workload.X509SVID do
  use Protobuf, syntax: :proto3

  field(:spiffe_id, 1, type: :string)
  field(:x509_svid, 2, type: :bytes)
  field(:x509_svid_key, 3, type: :bytes)
  field(:bundle, 4, type: :bytes)
  field(:hint, 5, type: :string)
end

defmodule SpiffeEx.Proto.Workload.X509SVIDResponse do
  use Protobuf, syntax: :proto3

  field(:svids, 1, repeated: true, type: SpiffeEx.Proto.Workload.X509SVID)
end

defmodule SpiffeEx.Proto.Workload.X509BundlesRequest do
  use Protobuf, syntax: :proto3
end

defmodule SpiffeEx.Proto.Workload.X509BundlesResponse.BundlesEntry do
  use Protobuf, map: true, syntax: :proto3

  field(:key, 1, type: :string)
  field(:value, 2, type: :bytes)
end

defmodule SpiffeEx.Proto.Workload.X509BundlesResponse do
  use Protobuf, syntax: :proto3

  field(:bundles, 1,
    repeated: true,
    type: SpiffeEx.Proto.Workload.X509BundlesResponse.BundlesEntry,
    map: true
  )
end

defmodule SpiffeEx.Proto.Workload.SpiffeWorkloadAPI.Service do
  use GRPC.Service, name: "spiffe.workload.SpiffeWorkloadAPI", protoc_gen_elixir_version: "0.11.0"

  rpc(
    :FetchJWTSVID,
    SpiffeEx.Proto.Workload.JWTSVIDRequest,
    SpiffeEx.Proto.Workload.JWTSVIDResponse
  )

  rpc(
    :FetchJWTBundles,
    SpiffeEx.Proto.Workload.JWTBundlesRequest,
    GRPC.Server.Stream
  )

  rpc(
    :ValidateJWTSVID,
    SpiffeEx.Proto.Workload.ValidateJWTSVIDRequest,
    SpiffeEx.Proto.Workload.ValidateJWTSVIDResponse
  )

  rpc(
    :FetchX509SVID,
    SpiffeEx.Proto.Workload.X509SVIDRequest,
    GRPC.Server.Stream
  )

  rpc(
    :FetchX509Bundles,
    SpiffeEx.Proto.Workload.X509BundlesRequest,
    GRPC.Server.Stream
  )
end

defmodule SpiffeEx.Proto.Workload.SpiffeWorkloadAPI.Stub do
  use GRPC.Stub, service: SpiffeEx.Proto.Workload.SpiffeWorkloadAPI.Service
end
