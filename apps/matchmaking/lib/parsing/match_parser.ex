defmodule Parsing.MatchParser do
  use GenServer
  alias Logging.MatchRecorder
  alias Matchmaking.Proxy.Utility
  alias Parsing.MatchState
  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    Logger.info("Matchmaking parser started...")

    {:ok, match_state} = GenServer.start_link(MatchState, :ok)

    {:ok, %{
      match_state: match_state
    }}
  end

  def parse(conn, ts, direction, {source, destination}, data) do
    GenServer.cast(__MODULE__, {:parse, conn, ts, direction, {source, destination}, data})
  end

  @impl true
  def handle_cast({:parse, conn, ts, direction, {source, destination}, data}, state) do
    {state, comment} = process_packet(conn, direction, {source, destination}, data, state)

    {source_host, source_port} = source
    {dest_host, dest_port} = source

    MatchRecorder.record(%{
      state: state.match_state,
      timestamp: ts,
      source: "#{Utility.host_to_ip(source_host)}:#{source_port}",
      destination: "#{Utility.host_to_ip(dest_host)}:#{dest_port}",
      direction: direction,
      comment: comment,
      data: data
    })

    {:noreply, state}
  end

  # Processes a packet from a client, headed to the server
  defp process_packet(_, :to_upstream, {source, _}, <<
    1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8
  >>, state) do
    {source_host, _} = source

    Logger.info("Hello Message (#{Utility.host_to_ip(source_host)})")
    {state, :hello}
  end

  defp process_packet(conn, :to_upstream, {source, _}, <<
    _header::binary-size(27),
    # "/Game/Maps/" encoded in ASCII * 2
    94, 142, 194, 218, 202, 94, 154, 194, 224, 230, 94,
    contents::binary
  >>, state) do
    [data_str | _] = :binary.split(contents, <<0>>)
    [_map_name | param_strs] = data_str
    |> Utility.reveal_strings()
    |> String.split("?")

    params = param_strs
    |> Enum.map(fn str -> String.split(str, "=", parts: 2) end)
    |> Map.new(fn [name, value] -> {name, value} end)
    |> update_in(["Perks"], fn val -> String.split(val, ",") |> Enum.reject(fn perk -> perk == "" end) end)
    |> update_in(["Stream"], fn val -> val == "1" end)

    {source_host, _} = source
    Logger.info("Player '#{Map.get(params, "Name")}' joined from #{Utility.host_to_ip(source_host)}")

    MatchState.set_player_info(state.match_state, conn, :username, Map.get(params, "Name"))

    {state, "Player Blob: #{inspect(params)}"}
  end

  defp process_packet(conn, :to_upstream, {source, _}, <<
    _header::binary-size(14),
    11, 0, 128, 1
  >>, state) do
    player_info = MatchState.get_player_info(state.match_state, conn)
    player_name = Map.get(player_info, :username, "Unknown player")

    {source_host, _} = source
    Logger.info("Player '#{player_name}' disconnected from #{Utility.host_to_ip(source_host)}")

    {state, "Player Disconnected: #{player_name}"}
  end



  defp process_packet(_, _, _, _, state), do: {state, false}
end
