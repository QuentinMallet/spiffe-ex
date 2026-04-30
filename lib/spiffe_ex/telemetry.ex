defmodule SpiffeEx.Telemetry do
  require Logger

  @events [
    [:spiffe_ex, :svid, :fetch],
    [:spiffe_ex, :svid, :cache_hit],
    [:spiffe_ex, :svid, :cache_miss],
    [:spiffe_ex, :token, :refresh],
    [:spiffe_ex, :error]
  ]

  def events, do: @events

  def attach_default_handlers do
    Enum.each(@events, fn event ->
      :telemetry.attach(
        "spiffe_ex-#{Enum.join(event, "-")}",
        event,
        &handle_event/4,
        nil
      )
    end)
  end

  def handle_event(event, measurements, metadata, _config) do
    Logger.info("SpiffeEx telemetry event",
      event: inspect(event),
      measurements: measurements,
      metadata: metadata
    )
  end
end
