defmodule SpiffeEx.Application do
  use Application

  def start(_type, _args) do
    ObservLib.configure()
    SpiffeEx.Telemetry.attach_default_handlers()

    children = []
    opts = [strategy: :one_for_one, name: SpiffeEx.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
