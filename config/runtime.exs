import Config

config :observlib,
  service_name: "spiffe_ex",
  log_level: :info

config :spiffe_ex, :observlib,
  log_level: :info,
  metrics: [],
  traces: []
