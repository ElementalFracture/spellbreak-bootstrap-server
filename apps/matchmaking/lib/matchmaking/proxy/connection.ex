defmodule Matchmaking.Proxy.Connection do
  alias Parsing.MatchParser
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, {
      Map.fetch!(opts, :identifier),
      Map.fetch!(opts, :match_parser),
      Map.fetch!(opts, :downstream_socket),
      Map.fetch!(opts, :direction),
      Map.fetch!(opts, :external_port),
      Map.fetch!(opts, :dest_host),
      Map.fetch!(opts, :dest_port)
    })
  end

  @impl true
  def init({
    identifier,
    match_parser,
    downstream_socket,
    direction,
    external_port,
    dest_host,
    dest_port
  }) do
    :gproc.reg({:p, :g, :proxy_connection})

    {:ok, socket} = if direction == :to_downstream do
      {:ok, downstream_socket}
    else
      :gen_udp.open(external_port, [:binary, active: true])
    end

    {:ok, %{
      identifier: identifier,
      match_parser: match_parser,
      socket: socket,
      direction: direction,
      dest_host: dest_host,
      dest_port: dest_port,
      forwarding_to: nil,
      player_info: %{}
    }}
  end

  def send(pid, {source_host, source_port}, data) do
    ts = DateTime.utc_now()
    GenServer.cast(pid, {:send, ts, source_host, source_port, data})
  end

  def close_if_host(pid, host), do: GenServer.cast(pid, {:close_if_host, host})

  def close(pid) do
    GenServer.cast(pid, :close)
  end

  def forward(pid, dest_pid) do
    GenServer.call(pid, {:forward, dest_pid})
  end

  def set_player_info(pid, key, value) do
    GenServer.cast(pid, {:set_player_info, key, value})
  end

  @impl true
  def handle_call({:forward, dest_pid}, _, state) do
    {:reply, :ok, %{ state | forwarding_to: dest_pid }}
  end

  @impl true
  def handle_cast({:set_player_info, key, value}, state) do
    {:noreply, put_in(state, [:player_info, key], value)}
  end

  @impl true
  def handle_cast({:close_if_host, host}, state) do
    if host == state.dest_host do
      GenServer.cast(self(), :close)
    end

    {:noreply, state}
  end

  @impl true
  def handle_cast(:close, %{direction: :to_downstream} = state) do
    {:stop, :normal, state}
  end

  def handle_cast(:close, %{socket: socket} = state) do
    :gen_udp.close(socket)

    {:stop, :normal, state}
  end

  @impl true
  def handle_cast({:send, ts, source_host, source_port, data}, %{socket: socket} = state) do
    MatchParser.parse(state.match_parser, state.identifier, ts, state.direction, {{source_host, source_port}, {state.dest_host, state.dest_port}}, data)
    case :gen_udp.send(socket, state.dest_host, state.dest_port, data) do
      :ok -> :ok
      {:error, :closed} -> :ok
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:udp, _socket, _host, _port, _data}, %{forwarding_to: nil} = state), do: {:noreply, state}

  @impl true
  def handle_info({:udp, _socket, host, port, data}, %{forwarding_to: dest_pid} = state) do
    send(dest_pid, {host, port}, data)
    {:noreply, state}
  end
end
