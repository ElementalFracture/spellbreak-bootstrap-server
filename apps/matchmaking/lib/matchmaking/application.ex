defmodule Matchmaking.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false
  use Application
  alias Matchmaking.Proxy

  @impl true
  def start(_type, _args) do
    servers = Application.fetch_env!(:matchmaking, :servers)
    outbound_port_start = Application.fetch_env!(:matchmaking, :outbound_port_start)
    outbound_port_end = Application.fetch_env!(:matchmaking, :outbound_port_end)
    chunk_length = Integer.floor_div(outbound_port_end-outbound_port_start, Enum.count(servers))
    outbound_port_list = Enum.to_list(outbound_port_start..outbound_port_end) |> Enum.chunk_every(chunk_length)

    server_children = servers |> Keyword.keys() |> Enum.zip(outbound_port_list) |> Enum.map(fn {server_name, outbound_ports} ->
      server_details = Keyword.fetch!(servers, server_name)

      base_settings = %{name: server_name, outbound_ports: outbound_ports}

      case server_details do
        {inbound_port, {host_ip_str, host_port}} ->
          host = IP.from_string!(host_ip_str)
          %{
            id: {:proxy, server_name},
            start: {Proxy.Server, :start_link, [Map.merge(base_settings, %{port: inbound_port, destination: {host, host_port}})]}
          }

        {inbound_port, {host_ip_str, host_port}, opts} ->
          host = IP.from_string!(host_ip_str)

          %{
            id: {:proxy, server_name},
            start: {Proxy.Server, :start_link, [Map.merge(base_settings, %{port: inbound_port, destination: {host, host_port}}), opts]}
          }
      end
    end)

    children = [
      {DynamicSupervisor, strategy: :one_for_one, name: Matchmaking.Proxy.Connections}
    ] ++ server_children

    children = if Application.get_env(:matchmaking, :discord_token) != nil do
      [{ChatBot.Bot, :ok}] ++ children
    else
      children
    end

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Matchmaking.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
