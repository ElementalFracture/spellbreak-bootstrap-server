defmodule Matchmaking.Proxy.Server do
  alias Matchmaking.Proxy.{Client, Clients, Utility}
  use GenServer
  require Logger

  @moduledoc """
  Handles incoming UDP communication with clients
  """

  # Outgoing UDP ports are attached to incoming Client IP/Port combos
  # These settings will reserve say, port 8000 to port 10000 for outgoing connections
  @outbound_port_start Application.compile_env(:matchmaking, :outbound_port_start)
  @outbound_port_end Application.compile_env(:matchmaking, :outbound_port_end)

  # After X minutes of client inactivity, recycle an outgoing port to be used by another client
  @recycle_ports_after_minutes Application.compile_env(:matchmaking, :recycle_ports_minutes)

  def start_link(port: port) do
    GenServer.start_link(__MODULE__, port)
  end

  @impl true
  def init(port) do
    {:ok, socket} = :gen_udp.open(port, [:binary, active: true])

    schedule_cleanup()

    {:ok, %{
      socket: socket,
      clients: %{},
      available_outbound: Enum.to_list(@outbound_port_start..@outbound_port_end)
    }}
  end

  @doc """
  Queues the sending packets from the server to the client
  """
  def send_downstream(pid, {client_ip, client_port}, data) do
    GenServer.cast(pid, {:send_downstream, {client_ip, client_port}, data})
  end

  # Handles sending packets from the server to the client
  @impl true
  def handle_cast({:send_downstream, {client_ip, client_port}, data}, state) do
    :ok = :gen_udp.send(state.socket, client_ip, client_port, data)

    {_, state} = process_data(data, state)
    {:noreply, state}
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
        client_port = Enum.random(state.available_outbound)
        available_outbound = state.available_outbound |> Enum.reject(&(&1 == client_port))

        {:ok, pid} = DynamicSupervisor.start_child(Clients, {Client, {client_port, {self(), host, port}}})
        Logger.info("New client connected from #{Utility.host_to_ip(host)} - Assigned to outbound port #{client_port}")

        client = {client_port, pid, DateTime.utc_now()}
        clients = Map.put(state.clients, client_id, client)

        {client, %{state |
          available_outbound: available_outbound,
          clients: clients
        }}

      {client, _} ->
        # We have seen this client before and they have an assigned outbound port
        {client_port, client_pid, _} = client
        new_client_state = {client_port, client_pid, DateTime.utc_now()}

        {client, put_in(state, [:clients, client_id], new_client_state)}
    end

    {_, client_pid, _} = client
    Client.send_upstream(client_pid, data)

    {:noreply, state}
  end

  # Recycles outbound ports when the client seems to have disappeared
  @impl true
  def handle_info(:cleanup, state) do
    newly_available_ports = Enum.reduce(state.clients, [], fn {client_id, client}, acc ->
      {client_host, _} = client_id
      {client_port, _, last_seen} = client

      if @recycle_ports_after_minutes <= DateTime.diff(DateTime.utc_now(), last_seen, :minute) do
        # Haven't seen a packet from this client in a while, add it to the recycle list
        Logger.info("Recycling outgoing port #{client_port} because #{Utility.host_to_ip(client_host)} hasn't used it in #{@recycle_ports_after_minutes} minutes...")

        [client_port | acc]
      else
        # We've received packets from this client recently. Leave it alone
        acc
      end
    end)

    schedule_cleanup()

    remaining_clients = Enum.reject(state.clients, fn client ->
      {_, {client_port, _, _}} = client

      Enum.member?(newly_available_ports, client_port)
    end)

    {:noreply, %{state | clients: remaining_clients, available_outbound: state.available_outbound ++ newly_available_ports}}
  end

  defp process_data(data, state), do: {data, state}

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @recycle_ports_after_minutes * 60 * 1000)
  end
end
