defmodule Matchmaking.MixProject do
  use Mix.Project

  def project do
    [
      app: :matchmaking,
      version: "0.1.0",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: [
        matchmaking: [
          include_executables_for: [:unix],
          applications: [runtime_tools: :permanent]
        ],
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :websockex, :gproc],
      mod: {Matchmaking.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
      {:file_system, "~> 1.0"},
      {:net_address, "~> 0.3.0"},
      {:websockex, "~> 0.4.3"},
      {:req, "~> 0.4.0"},
      {:jason, "~> 1.4"},
      {:gproc, "~> 0.9.1"},
      {:libcluster, "~> 3.3.3"}
    ]
  end
end
