defmodule Matchmaking.Proxy.Client do
  alias Matchmaking.Proxy.Server
  use GenServer
  require Logger

  @moduledoc """
  Routes requests/responses for a specific client through a designated port
  """

  @upstream_ip {192, 168, 86, 111}
  @upstream_port 7777

  def start_link({port, downstream}) do
    GenServer.start_link(__MODULE__, {port, downstream})
  end

  @impl true
  def init({port, downstream}) do
    {:ok, socket} = :gen_udp.open(port, [:binary, active: true])
    {:ok, %{
      socket: socket,
      downstream: downstream
    }}
  end

  def send_upstream(pid, data) do
    GenServer.cast(pid, {:send_upstream, data})
  end

  @impl true
  def handle_cast({:send_upstream, data}, state) do
    :ok = :gen_udp.send(state.socket, @upstream_ip, @upstream_port, data)

    data
    |> IO.inspect(label: "sent_upstream")

    {:noreply, state}
  end

  @impl true
  def handle_info({:udp, _socket, host, port, data}, state) do
    if host == @upstream_ip && port == @upstream_port do
      {downstream_pid, client_ip, client_port} = state.downstream
      Server.send_downstream(downstream_pid, {client_ip, client_port}, data)
    end

    {:noreply, state}
  end
end
