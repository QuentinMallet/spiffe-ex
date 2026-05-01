defmodule SpiffeEx.SvidCache do
  use GenServer
  require Logger

  @default_refresh_buffer_secs 30
  @ets_key :current_svid

  # Public API

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: via(name))
  end

  def get(name) do
    table = ets_table(name)

    case :ets.lookup(table, @ets_key) do
      [{@ets_key, svid}] ->
        if not expired?(svid) do
          :telemetry.execute([:spiffe_ex, :svid, :cache_hit], %{}, %{spiffe_id: svid.spiffe_id})
          {:ok, svid}
        else
          :telemetry.execute([:spiffe_ex, :svid, :cache_miss], %{}, %{})
          GenServer.call(via(name), :get)
        end

      [] ->
        :telemetry.execute([:spiffe_ex, :svid, :cache_miss], %{}, %{})
        GenServer.call(via(name), :get)
    end
  rescue
    ArgumentError ->
      :telemetry.execute([:spiffe_ex, :svid, :cache_miss], %{}, %{})
      GenServer.call(via(name), :get)
  end

  defp via(name), do: {:via, Registry, {SpiffeEx.Registry, {name, :svid_cache}}}
  defp ets_table(name), do: :"#{name}_svid_ets"

  # GenServer callbacks

  @impl true
  def init(opts) do
    name = Keyword.fetch!(opts, :name)

    opts =
      if Keyword.has_key?(opts, :socket_path) and not Keyword.has_key?(opts, :endpoint) do
        Logger.warning("SpiffeEx: :socket_path is deprecated, use :endpoint instead (e.g. endpoint: \"unix:#{Keyword.fetch!(opts, :socket_path)}\")")
        Keyword.put(opts, :endpoint, "unix:#{Keyword.fetch!(opts, :socket_path)}")
      else
        opts
      end

    table = :ets.new(ets_table(name), [:set, :public, :named_table, {:read_concurrency, true}])

    state = %{
      svid: nil,
      opts: opts,
      refresh_timer: nil,
      ets_table: table
    }

    send(self(), :refresh)
    {:ok, state}
  end

  @impl true
  def handle_call(:get, _from, state) do
    case fetch_svid(state) do
      {:ok, svid, new_state} ->
        {:reply, {:ok, svid}, new_state}

      {:error, reason, new_state} ->
        {:reply, {:error, reason}, new_state}
    end
  end

  @impl true
  def handle_info(:refresh, state) do
    workload_mod = Keyword.get(state.opts, :workload_api_mod, SpiffeEx.WorkloadAPI.GrpcAdapter)
    endpoint = resolve_endpoint(state.opts)
    grpc_opts = resolve_grpc_opts(state.opts)
    audience = Keyword.get(state.opts, :audience, [])

    case workload_mod.fetch_jwt_svid(endpoint, audience, grpc_opts) do
      {:ok, svid} ->
        :ets.insert(state.ets_table, {@ets_key, svid})
        timer = schedule_refresh(svid, state.opts)

        if state.refresh_timer, do: Process.cancel_timer(state.refresh_timer)

        {:noreply, %{state | svid: svid, refresh_timer: timer}}

      {:error, _reason} ->
        {:noreply, state}
    end
  end

  # Private helpers

  defp fetch_svid(state) do
    workload_mod = Keyword.get(state.opts, :workload_api_mod, SpiffeEx.WorkloadAPI.GrpcAdapter)
    endpoint = resolve_endpoint(state.opts)
    grpc_opts = resolve_grpc_opts(state.opts)
    audience = Keyword.get(state.opts, :audience, [])

    case workload_mod.fetch_jwt_svid(endpoint, audience, grpc_opts) do
      {:ok, svid} ->
        :ets.insert(state.ets_table, {@ets_key, svid})
        timer = schedule_refresh(svid, state.opts)

        if state.refresh_timer, do: Process.cancel_timer(state.refresh_timer)

        {:ok, svid, %{state | svid: svid, refresh_timer: timer}}

      {:error, _reason} ->
        {:error, :workload_api_unavailable, state}
    end
  end

  defp schedule_refresh(svid, opts) do
    buffer = Keyword.get(opts, :refresh_buffer_secs, @default_refresh_buffer_secs)
    ms = DateTime.diff(svid.expires_at, DateTime.utc_now(), :millisecond) - buffer * 1_000
    ms = max(0, ms)
    Process.send_after(self(), :refresh, ms)
  end

  defp resolve_endpoint(opts) do
    Keyword.fetch!(opts, :endpoint)
  end

  defp resolve_grpc_opts(opts) do
    Keyword.get(opts, :grpc_opts, [])
  end

  defp expired?(%SpiffeEx.SVID{expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), DateTime.add(expires_at, -1, :second)) == :gt
  end
end
