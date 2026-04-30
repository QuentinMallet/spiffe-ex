defmodule SpiffeEx.MixProject do
  use Mix.Project

  def project do
    [
      app: :spiffe_ex,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger],
      mod: {SpiffeEx.Application, []}
    ]
  end

  defp deps do
    [
      # gRPC for SPIFFE Workload API
      {:grpc, "~> 0.9"},
      {:protobuf, "~> 0.14"},
      # OIDC
      {:oidcc, "~> 3.0"},
      {:jose, "~> 1.11"},
      # Ash core
      {:ash, "~> 3.0"},
      # Observability
      {:observlib, github: "ForgottenBeast/observlib-ex"},
      # Testing
      {:stream_data, "~> 1.0"},
      {:snabbkaffe, "~> 1.0", only: :test}
    ]
  end
end
