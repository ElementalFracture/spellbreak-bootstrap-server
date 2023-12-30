defmodule Matchmaking.Proxy.MatchManager do
  use GenServer
  require Logger

  @global_group :matchmaking_match_manager
  @sub_name inspect(__MODULE__)

  def start_link(args, opts \\ []) do
    GenServer.start_link(__MODULE__, args, opts)
  end

  @impl true
  def init(args) do
    {:ok, %{
      server_name: Map.fetch!(args, :server_name),
      server_host: Map.fetch!(args, :server_host),
      server_manager_port: Map.get(args, :server_manager_port),
    }, {:continue, :setup}}
  end

  @impl true
  def handle_continue(:setup, state) do
    Swarm.join(@global_group, self())

    {:noreply, state}
  end

  def server_name(pid), do: GenServer.call(pid, :server_name)
  def reset_server(pid), do: GenServer.call(pid, :reset_server, 5_000)
  def get_status(pid), do: GenServer.call(pid, :get_status, 5_000)
  def has_server_manager?(pid), do: GenServer.call(pid, :has_server_manager?)

  @impl true
  def handle_call(:server_name, _, state) do
    {:reply, state.server_name, state}
  end

  @impl true
  def handle_call(:has_server_manager?, _, state) do
    {:reply, state.server_manager_port != nil, state}
  end

  @impl true
  def handle_call(:get_status, {from, _}, state) do
    Logger.info("Fetching server status: #{inspect(state)}")

    try do
      {:ok, socket} = :gen_tcp.connect(state.server_host, 4951, [
        active: false,
        mode: :binary,
        packet: :line,
        recbuf: 10_000_000,
        send_timeout: 1_000,
        send_timeout_close: true
      ], 1_000)

      Logger.info("Connected to #{inspect(state.server_host)} Match Tracker TCP...")

      :ok = :gen_tcp.send(socket, "get_players\n")
      Logger.info("Sent get_players to Match Tracker...")

      case :gen_tcp.recv(socket, 0, 1_000) do
        {:ok, data} ->
          data |> IO.inspect(label: "'get_players' (#{inspect(state.server_host)})")
          :gen_tcp.close(socket)
          {:reply, Jason.decode(data), state}

        {:error, err} ->
          Logger.warning("Error from 'get_players' command -> #{inspect(state.server_host)} (#{inspect(err)})...")
          :gen_tcp.close(socket)
          {:reply, {:error, err}, state}

      end
    rescue
      err ->
        Logger.error("Error with get_status -> #{inspect(state.server_host)} (#{inspect(err)})...")
        {:reply, {:error, inspect(err)}, state}
    end
  end

  @impl true
  def handle_call(:reset_server, _, state) do
    Logger.info("Sending reset signal: #{inspect(state)}")

    try do
      {:ok, socket} = :gen_tcp.connect(state.server_host, state.server_manager_port, [
        active: false,
        mode: :binary,
        packet: :raw,
        send_timeout: 2_000,
        send_timeout_close: true
      ], 2_000)
      :ok = :gen_tcp.send(socket, "CMD_REFRESH")
      :gen_tcp.close(socket)

      {:reply, :ok, state}
    rescue
      err -> {:reply, {:error, err}, state}
    end
  end

  def global_group, do: @global_group
end
