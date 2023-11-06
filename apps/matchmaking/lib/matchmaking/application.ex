defmodule Matchmaking.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false
  use Application
  alias Matchmaking.Proxy

  @impl true
  def start(_type, _args) do
    inbound_port = Application.fetch_env!(:matchmaking, :inbound_port)

    children = [
      {DynamicSupervisor, strategy: :one_for_one, name: Matchmaking.Proxy.Connections},
      {Logging.MatchRecorder, [base_directory: "tmp/recordings"]},
      {Proxy.Server, [port: inbound_port]},
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Matchmaking.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
