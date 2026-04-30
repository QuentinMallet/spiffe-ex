defmodule SpiffeEx do
  @moduledoc """
  SpiffeEx — Elixir library for SPIFFE/SPIRE workload identity and OIDC federation.

  ## Usage

      {:ok, _pid} = SpiffeEx.start_link(
        provider_uri: "https://idp.example.com",
        client_id: "my-client",
        socket_path: "/run/spire/sockets/agent.sock"
      )

      {:ok, %SpiffeEx.Token{}} = SpiffeEx.authenticate()
  """

  use Supervisor
  require Logger

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @spec authenticate(name :: atom()) :: {:ok, SpiffeEx.Token.t()} | {:error, atom()}
  def authenticate(name \\ __MODULE__) do
    :telemetry.span([:spiffe_ex, :authenticate], %{}, fn ->
      result = SpiffeEx.TokenCache.get(name)
      {result, %{}}
    end)
  end

  @spec fetch_svid(name :: atom(), opts :: keyword()) ::
          {:ok, SpiffeEx.SVID.t()} | {:error, atom()}
  def fetch_svid(name \\ __MODULE__, _opts \\ []) do
    SpiffeEx.SvidCache.get(name)
  end

  @spec status(name :: atom()) :: map()
  def status(name \\ __MODULE__) do
    svid_result = SpiffeEx.SvidCache.get(name)
    token_result = SpiffeEx.TokenCache.get(name)

    %{
      svid_expires_at:
        case svid_result do
          {:ok, s} -> s.expires_at
          _ -> nil
        end,
      token_expires_at:
        case token_result do
          {:ok, t} -> t.expires_at
          _ -> nil
        end,
      healthy: match?({:ok, _}, svid_result) and match?({:ok, _}, token_result)
    }
  end

  @impl Supervisor
  def init(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    provider_uri = Keyword.get(opts, :provider_uri)

    oidcc_worker_name = SpiffeEx.OidcClient.provider_worker_name(name)

    oidcc_children =
      if provider_uri do
        [
          {Oidcc.ProviderConfiguration.Worker,
           %{issuer: provider_uri, name: oidcc_worker_name}}
        ]
      else
        []
      end

    children =
      [
        GRPC.Client.Supervisor,
        {Registry, keys: :unique, name: SpiffeEx.Registry},
        {SpiffeEx.SvidCache, [{:name, name} | opts]},
        {SpiffeEx.TokenCache, [{:name, name} | opts]}
      ] ++ oidcc_children

    Supervisor.init(children, strategy: :one_for_one)
  end
end
