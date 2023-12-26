defmodule Matchmaking.Proxy.MatchManager do
  use GenServer
  require Logger

  @global_group :matchmaking_match_manager

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
  def reset_server(pid), do: GenServer.call(pid, :reset_server, 30_000)
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
