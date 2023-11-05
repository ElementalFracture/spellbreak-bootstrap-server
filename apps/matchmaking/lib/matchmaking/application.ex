defmodule Matchmaking.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false
  use Application
  alias Matchmaking.DiscordBot
  alias Matchmaking.Proxy

  # Accept client connections on this port
  @inbound_port Application.compile_env(:matchmaking, :inbound_port)

  @impl true
  def start(_type, _args) do
    children = [
      {DynamicSupervisor, strategy: :one_for_one, name: Matchmaking.Proxy.Clients},
      {Proxy.Server, [port: @inbound_port]},
    ]

    children = if System.get_env("DISCORD_BOT") == "1" do
      children ++ [{DiscordBot.GatewayClient, :ok}]
    else
      children
    end

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Matchmaking.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
