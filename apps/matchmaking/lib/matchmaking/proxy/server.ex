defmodule Matchmaking.Proxy.Server do
  alias Matchmaking.Proxy.{Connection, Connections, Utility}
  alias Parsing.MatchState
  use GenServer
  require Logger

  @moduledoc """
  Handles incoming UDP communication with clients
  """

  def start_link(port: port) do
    GenServer.start_link(__MODULE__, port)
  end

  @impl true
  def init(port) do
    {:ok, socket} = :gen_udp.open(port, [:binary, active: true])
    {:ok, match_parser} = Parsing.MatchParser.start_link([])

    outbound_port_start = Application.fetch_env!(:matchmaking, :outbound_port_start)
    outbound_port_end = Application.fetch_env!(:matchmaking, :outbound_port_end)

    schedule_cleanup()

    {:ok, %{
      socket: socket,
      match_parser: match_parser,
      clients: %{},
      available_outbound: Enum.to_list(outbound_port_start..outbound_port_end)
    }}
  end

  # Received a UDP packet from the client, to forward to the server
  @impl true
  def handle_info({:udp, _socket, host, port, data}, state) do
    client_id = {host, port}
    {client, state} = case {Map.get(state.clients, client_id), state} do
      {nil, %{available_outbounds: []}} ->
        # We have no available outbound ports
        Logger.warning("New client (#{Utility.host_to_ip(host)}) tried to connect when there are no outbound ports available. Ignoring")

        {:noreply, state}

      {nil, _} ->
        # We have a new client and also available outbound ports
        [external_upstream_port, external_downstream_port] = Enum.take_random(state.available_outbound, 2)
        available_outbound = state.available_outbound |> Enum.reject(&(Enum.member?([external_upstream_port, external_downstream_port], &1)))

        {:ok, downstream_conn} = DynamicSupervisor.start_child(Connections, {Connection, [
          match_parser: state.match_parser,
          downstream_socket: state.socket,
          direction: :to_downstream,
          external_port: external_downstream_port,
          dest_host: host,
          dest_port: port,
          identifier: client_id
        ]})

        {:ok, upstream_conn} = DynamicSupervisor.start_child(Connections, {Connection, [
          match_parser: state.match_parser,
          downstream_socket: state.socket,
          direction: :to_upstream,
          external_port: external_upstream_port,
          dest_host: Application.fetch_env!(:matchmaking, :upstream_ip),
          dest_port: Application.fetch_env!(:matchmaking, :upstream_port),
          identifier: client_id
        ]})

        Connection.forward(downstream_conn, upstream_conn)
        Connection.forward(upstream_conn, downstream_conn)

        Logger.info("New client connected from #{Utility.host_to_ip(host)} - Assigned to outbound port #{external_upstream_port}")

        client = {[
          {external_downstream_port, downstream_conn},
          {external_upstream_port, upstream_conn}
        ], DateTime.utc_now()}

        clients = Map.put(state.clients, client_id, client)

        {client, %{state |
          available_outbound: available_outbound,
          clients: clients
        }}

      {client, _} ->
        # We have seen this client before and they have an assigned outbound port
        {conns, _} = client

        {client, put_in(state, [:clients, client_id], {conns, DateTime.utc_now()})}
    end

    {[_, {_, upstream_conn}], _} = client
    Connection.send(upstream_conn, {host, port}, data)

    {:noreply, state}
  end

  # Recycles outbound ports when the client seems to have disappeared
  @impl true
  def handle_info(:cleanup, state) do
    recycle_port_ttl = Application.fetch_env!(:matchmaking, :recycle_ports_minutes)

    removed_client_ids = Enum.reduce(state.clients, [], fn {client_id, client}, acc ->
      {conns, last_seen} = client

      if (60 * recycle_port_ttl) <= DateTime.diff(DateTime.utc_now(), last_seen, :second) do
        # Haven't seen a packet from this client in a while, add it to the recycle list
        Enum.each(conns, fn {_, conn} ->
          Connection.close(conn)
        end)

        [client_id | acc]
      else
        # We've received packets from this client recently. Leave it alone
        acc
      end
    end)

    schedule_cleanup()

    remaining_clients = Map.drop(state.clients, removed_client_ids)
    removed_clients = Map.take(state.clients, removed_client_ids)
    newly_available_ports = Enum.reduce(removed_clients, [], fn {_, client}, acc ->
      {conns, _} = client
      new_ports = Enum.map(conns, fn {port, _} -> port end)

      new_ports ++ acc
    end)

    match_state = Parsing.MatchParser.match_state(state.match_parser)
    if removed_clients > 0 do
      removed_clients |> Enum.map(fn {{host, port}, _} ->
        player_info = MatchState.get_player_info(match_state, {host, port})
        player_name = Map.get(player_info, :username, "Unknown player")

        Logger.info("Recycling ports for #{Utility.host_to_ip(host)}:#{port} (#{player_name}) since they've been missing for #{recycle_port_ttl} minutes...")
      end)
    end

    cond do
      Enum.count(removed_clients) > 0 && Enum.count(remaining_clients) > 0 ->
        Logger.info("Remaining clients:")
        remaining_clients |> Enum.map(fn {{host, port}, _} ->
          player_info = MatchState.get_player_info(match_state, {host, port})
          player_name = Map.get(player_info, :username, "Unknown player")
          Logger.info("- #{Utility.host_to_ip(host)}:#{port} (#{player_name})")
        end)

      Enum.count(removed_clients) > 0 ->
        Logger.info("No remaining clients")

      true -> :ok
    end

    {:noreply, %{state | clients: remaining_clients, available_outbound: state.available_outbound ++ newly_available_ports}}
  end

  defp schedule_cleanup do
    recycle_port_ttl = Application.fetch_env!(:matchmaking, :recycle_ports_minutes)
    Process.send_after(self(), :cleanup, recycle_port_ttl * 60 * 1000)
  end
end
