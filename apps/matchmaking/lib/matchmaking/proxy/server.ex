defmodule Matchmaking.Proxy.Server do
  alias Matchmaking.Proxy.{Client, Clients}
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

    {:ok, %{
      socket: socket,
      clients: %{},
      available_outbound: Enum.to_list(8000..9000)
    }}
  end

  def send_downstream(pid, {client_ip, client_port}, data) do
    GenServer.cast(pid, {:send_downstream, {client_ip, client_port}, data})
  end

  @impl true
  def handle_cast({:send_downstream, {client_ip, client_port}, data}, state) do
    :ok = :gen_udp.send(state.socket, client_ip, client_port, data)

    {_, state} = process_data(data, state)

    # data
    # |> IO.inspect(label: "sent_downstream", limit: :infinity)

    {:noreply, state}
  end

  @impl true
  def handle_info({:udp, _socket, host, port, data}, state) do
    client_id = {host, port}
    {client, state} = case Map.get(state.clients, client_id) do
      nil ->
        client_port = Enum.random(state.available_outbound)
        available_outbound = state.available_outbound |> Enum.reject(&(&1 == client_port))

        {:ok, pid} = DynamicSupervisor.start_child(Clients, {Client, {client_port, {self(), host, port}}})
        client_port |> IO.inspect(label: "new_client")

        client = {client_port, pid}
        clients = Map.put(state.clients, client_id, client)

        {client, %{state |
          available_outbound: available_outbound,
          clients: clients
        }}

      client ->
        {client, state}
    end

    {_, client_pid} = client
    Client.send_upstream(client_pid, data)

    {:noreply, state}
  end

  defp process_data(<<
      _remaining::binary
    >> = data, state) do
    # Logger.info("server: #{inspect(remaining, limit: :infinity)}")

    {data, state}
  end
end
