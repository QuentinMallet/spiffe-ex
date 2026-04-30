defmodule SpiffeEx.TokenCache do
  use GenServer
  require Logger

  @default_refresh_buffer_secs 30

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: via(name))
  end

  def get(name), do: GenServer.call(via(name), :get)

  defp via(name), do: {:via, Registry, {SpiffeEx.Registry, {name, :token_cache}}}

  @impl GenServer
  def init(opts) do
    name = Keyword.fetch!(opts, :name)
    table = :ets.new(:"spiffe_ex_token_#{name}", [:set, :protected, :named_table])

    {:ok,
     %{
       token: nil,
       opts: opts,
       refresh_timer: nil,
       ets_table: table
     }}
  end

  @impl GenServer
  def handle_call(:get, _from, state) do
    case read_valid_token(state) do
      {:ok, token} ->
        {:reply, {:ok, token}, state}

      :miss ->
        case fetch_and_store(state) do
          {:ok, token, new_state} ->
            {:reply, {:ok, token}, new_state}

          {:error, reason, new_state} ->
            :telemetry.execute([:spiffe_ex, :error], %{}, %{reason: reason})
            {:reply, {:error, reason}, new_state}
        end
    end
  end

  @impl GenServer
  def handle_info(:refresh, state) do
    case fetch_and_store(state) do
      {:ok, _token, new_state} ->
        {:noreply, new_state}

      {:error, reason, new_state} ->
        Logger.warning("SpiffeEx.TokenCache proactive refresh failed: #{inspect(reason)}")
        :telemetry.execute([:spiffe_ex, :error], %{}, %{reason: reason})
        {:noreply, new_state}
    end
  end

  defp read_valid_token(state) do
    buffer = Keyword.get(state.opts, :refresh_buffer_secs, @default_refresh_buffer_secs)

    case :ets.lookup(state.ets_table, :current_token) do
      [{:current_token, token, expires_at}] ->
        threshold = DateTime.add(DateTime.utc_now(), buffer, :second)

        if DateTime.compare(expires_at, threshold) == :gt do
          {:ok, token}
        else
          :miss
        end

      [] ->
        :miss
    end
  end

  defp fetch_and_store(state) do
    name = Keyword.fetch!(state.opts, :name)

    with {:ok, svid} <- SpiffeEx.SvidCache.get(name),
         {:ok, token} <- SpiffeEx.OidcClient.retrieve_token(svid.token, state.opts) do
      :ets.insert(state.ets_table, {:current_token, token, token.expires_at})
      :telemetry.execute([:spiffe_ex, :token, :refresh], %{}, %{})

      timer = schedule_refresh(token.expires_at, state.opts)

      if state.refresh_timer, do: Process.cancel_timer(state.refresh_timer)

      new_state = %{state | token: token, refresh_timer: timer}
      {:ok, token, new_state}
    else
      {:error, reason} ->
        {:error, reason, state}
    end
  end

  defp schedule_refresh(expires_at, opts) do
    buffer = Keyword.get(opts, :refresh_buffer_secs, @default_refresh_buffer_secs)
    refresh_at = DateTime.add(expires_at, -buffer, :second)
    diff_ms = DateTime.diff(refresh_at, DateTime.utc_now(), :millisecond)
    delay = max(diff_ms, 0)
    Process.send_after(self(), :refresh, delay)
  end
end
