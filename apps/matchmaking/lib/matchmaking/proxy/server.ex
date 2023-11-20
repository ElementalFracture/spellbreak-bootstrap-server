defmodule Matchmaking.Proxy.Server do
  alias Matchmaking.Proxy.BanHandler
  alias Matchmaking.Proxy.{Connection, Connections, Utility}
  alias Parsing.{MatchParser, MatchState}
  alias Logging.{MatchLogger, MatchRecorder}
  use GenServer
  require Logger

  @moduledoc """
  Handles incoming UDP communication with clients
  """

  def start_link(%{
    name: name,
    port: port,
    destination: dest,
    outbound_ports: outbound_ports
  }, opts \\ %{}) do
    opts = Map.put(opts, :name, name)
    opts = Map.put(opts, :destination, dest)

    GenServer.start_link(__MODULE__, [port, outbound_ports, opts])
  end

  @impl true
  def init([port, outbound_ports, opts]) do
    {:ok, socket} = :gen_udp.open(port, [:binary, active: true])

    server_name = Map.get(opts, :name, :no_name)
    {host, host_port} = opts.destination
    Logger.info("Proxy #{server_name} started, pointing 0.0.0.0:#{port} -> #{IP.to_string(host)}:#{host_port}")

    match_logger_id = via_tuple({:match_logger, opts.name})
    match_state_id = via_tuple({:match_state, opts.name})
    match_recorder_id = via_tuple({:match_recorder, opts.name})
    match_parser_id = via_tuple({:match_parser, opts.name})
    children = [
      %{
        id: MatchLogger,
        start: {MatchLogger, :start_link, [%{
          log_directory: Map.get(opts, :log_dir)
        }, [name: match_logger_id]]}
      },
      %{
        id: MatchRecorder,
        start: {MatchRecorder, :start_link, [%{
          recording_directory: Map.get(opts, :recording_dir)
        }, [name: match_recorder_id]]}
      },
      %{
        id: MatchState,
        start: {MatchState, :start_link, [%{
          server_name: server_name,
          logger: match_logger_id,
          recorder: match_recorder_id,
          log_directory: Map.get(opts, :log_dir)
        }, [name: match_state_id]]}
      },
      %{
        id: MatchParser,
        start: {MatchParser, :start_link, [%{
          logger: match_logger_id,
          match_state: match_state_id,
          recorder: match_recorder_id
        }, [name: match_parser_id]]}
      }
    ]

    supervisor_id = via_tuple({:match_supervisor, opts.name})
    {:ok, supervisor} = Supervisor.start_link(children, [strategy: :one_for_one, name: supervisor_id])

    schedule_cleanup()

    {:ok, %{
      socket: socket,
      supervisor: supervisor,
      logger: match_logger_id,
      match_parser: match_parser_id,
      match_state: match_state_id,
      recorder: match_recorder_id,
      clients: %{},
      opts: opts,
      available_outbound: outbound_ports
    }}
  end

  # Received a UDP packet from the client, to forward to the server
  @impl true
  def handle_info({:udp, _socket, host, port, data}, state) do
    client_id = {host, port}
    existing_connection = Map.get(state.clients, client_id)

    {client, state} = cond do
      existing_connection == nil && Enum.empty?(state.available_outbound) ->
        # We have no available outbound ports
        Logger.warning("New client (#{Utility.host_to_ip(host)}) tried to connect when there are no outbound ports available. Ignoring")
        {nil, state}

      existing_connection == nil && BanHandler.is_banned?(host) ->
        # Ignore the connection request. This person has been banned
        Logger.warning("Attempt to connect from banned host '#{Utility.host_to_ip(host)}'. Ignoring...")
        {nil, state}

      existing_connection == nil ->
        # We have a new client and also available outbound ports
        [external_upstream_port, external_downstream_port] = Enum.take_random(state.available_outbound, 2)
        available_outbound = state.available_outbound |> Enum.reject(&(Enum.member?([external_upstream_port, external_downstream_port], &1)))

        {:ok, downstream_conn} = DynamicSupervisor.start_child(Connections, {Connection, %{
          match_parser: state.match_parser,
          downstream_socket: state.socket,
          direction: :to_downstream,
          external_port: external_downstream_port,
          dest_host: host,
          dest_port: port,
          identifier: client_id
        }})

        {dest_host, dest_port} = state.opts[:destination]
        {:ok, upstream_conn} = DynamicSupervisor.start_child(Connections, {Connection, %{
          match_parser: state.match_parser,
          downstream_socket: state.socket,
          direction: :to_upstream,
          external_port: external_upstream_port,
          dest_host: dest_host,
          dest_port: dest_port,
          identifier: client_id
        }})

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

      true ->
        # We have seen this client before and they have an assigned outbound port
        {conns, _} = existing_connection

        {existing_connection, put_in(state, [:clients, client_id], {conns, DateTime.utc_now()})}
    end

    if client do
      {[_, {_, upstream_conn}], _} = client
      Connection.send(upstream_conn, {host, port}, data)
    end

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

    if removed_clients > 0 do
      removed_clients |> Enum.map(fn {{host, port}, _} ->
        player_info = MatchState.get_player_info(state.match_state, {host, port})
        player_name = Map.get(player_info, :username, "Unknown player")

        Logger.info("Recycling ports for #{Utility.host_to_ip(host)}:#{port} (#{player_name}) since they've been missing for #{recycle_port_ttl} minutes...")
      end)
    end

    cond do
      Enum.count(removed_clients) > 0 && Enum.count(remaining_clients) > 0 ->
        Logger.info("Remaining clients:")
        remaining_clients |> Enum.map(fn {{host, port}, _} ->
          player_info = MatchState.get_player_info(state.match_state, {host, port})
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

  defp via_tuple(name_tuple), do: {:via, :gproc, {:n, :l, name_tuple}}
end
