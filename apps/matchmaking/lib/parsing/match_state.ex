defmodule Parsing.MatchState do
  use GenServer
  require Logger
  alias Logging.{MatchLogger, MatchRecorder}
  alias Matchmaking.Proxy.Utility

  @log_regex ~r/.*\/g3-([0-9]+)\.log$/
  @gproc_prop :matchmaking_match_state

  def start_link(args, opts \\ []) do
    GenServer.start_link(__MODULE__, args, opts)
  end

  @impl true
  def init(args) do
    {:ok, %{
      game_id: nil,
      server_name: Map.fetch!(args, :server_name),
      log_dir: Map.get(args, :log_directory),
      logger: Map.get(args, :logger),
      recorder: Map.get(args, :recorder),
      players: %{}
    }, {:continue, :setup_watchers}}
  end

  @impl true
  def handle_continue(:setup_watchers, state) do
    :gproc.reg({:p, :g, @gproc_prop})

    if state.log_dir do
      {:ok, pid} = FileSystem.start_link(dirs: [state.log_dir])
      FileSystem.subscribe(pid)
    end

    {:noreply, state}
  end

  def set_player_info(pid, conn, key, value) do
    GenServer.cast(pid, {:set_player_info, conn, key, value})
  end

  def get_player_info(pid, conn) do
    GenServer.call(pid, {:get_player_info, conn})
  end

  def server_name(pid), do: GenServer.call(pid, :server_name)
  def players_and_ips(pid), do: GenServer.call(pid, :players_and_ips)

  @impl true
  def handle_cast({:set_player_info, conn, key, value}, state) do
    players = state.players

    players = if Map.has_key?(players, conn) do
      put_in(players, [conn, key], value)
    else
      Map.put(players, conn, %{key => value})
    end

    {:noreply, %{state | players: players}}
  end

  @impl true
  def handle_call(:server_name, _, state) do
    {:reply, state.server_name, state}
  end

  @impl true
  def handle_call(:players_and_ips, _, state) do
    pairs = state.players
    |> Enum.map(fn
      {{{_, _, _, _} = host, _}, player} -> {Utility.host_to_ip(host), player}
      _ -> nil
    end)

    {:reply, pairs, state}
  end

  @impl true
  def handle_call({:get_player_info, conn}, _, state) do
    {:reply, Map.get(state.players, conn, %{}), state}
  end

  @impl true
  def handle_info({:file_event, _watcher_pid, {file_path, events}}, state) do
    cond do
      Enum.member?(events, :created) && Regex.match?(@log_regex, file_path) ->
        [[_, game_id]] = Regex.scan(@log_regex, file_path)

        Logger.info("#{state.server_name} Detected #{file_path} - Updating Game ID to #{game_id}")
        if state.logger, do: MatchLogger.set_match_name(state.logger, "g3-#{game_id}")
        if state.recorder, do: MatchRecorder.set_match_name(state.recorder, "g3-#{game_id}")

        {:noreply, %{state | game_id: game_id, players: %{}}}

      true -> {:noreply, state}
    end
  end


  @impl true
  def handle_info({:file_event, _watcher_pid, :stop}, state) do
    {:noreply, state}
  end

  def gproc_prop, do: @gproc_prop
end
