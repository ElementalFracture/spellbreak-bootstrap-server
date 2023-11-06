defmodule Parsing.MatchParser do
  use GenServer
  alias Logging.MatchRecorder
  alias Matchmaking.Proxy.Utility
  alias Parsing.MatchState
  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok)
  end

  @impl true
  def init(:ok) do
    Logger.info("Matchmaking parser started...")

    {:ok, match_state} = GenServer.start_link(MatchState, :ok)

    {:ok, %{
      match_state: match_state
    }}
  end

  def parse(pid, conn, ts, direction, {source, destination}, data) do
    GenServer.cast(pid, {:parse, conn, ts, direction, {source, destination}, data})
  end

  def wait(pid) do
    GenServer.call(pid, :wait, 6000000)
  end

  @impl true
  def handle_cast({:parse, conn, ts, direction, {source, destination}, data}, state) do
    {data, state, comment} = case process_packet(conn, direction, {source, destination}, data, state) do
      {new_data, state, comment} -> {new_data, state, comment}
      {state, comment} -> {data, state, comment}
    end

    {source_host, source_port} = source
    {dest_host, dest_port} = destination

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

  @impl true
  def handle_call(:wait, _, state) do
    {:reply, :ok, state}
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
  >> = data, state) do
    [data_str | _] = :binary.split(contents, <<0>>)
    [map_name | param_strs] = data_str
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

    {data, state, "Player Blob: #{inspect(params)}"}
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

  defp process_packet(_, :to_upstream, _, <<_header::binary-size(9), 128, 1, 28, 130, 249, 2, 210, 101, 129, _::binary>>, state) do
    {state, "Heartbeat??"}
  end

  defp process_packet(_, :to_upstream, _, <<__header::binary-size(9), 24>>, state) do
    {state, "Handshake??"}
  end

  defp process_packet(_, :to_downstream, _, <<__header::binary-size(11), 1, 116, 128, 96, 46, 161, _::binary>>, state) do
    {state, "Heartbeat Request 1??"}
  end

  defp process_packet(_, :to_downstream, _, <<__header::binary-size(21), 48, 128, 14, 16, 204, 37, _::binary-size(4), 104>>, state) do
    {state, "Heartbeat Request 2??"}
  end

  defp process_packet(_, :to_downstream, _, <<__header::binary-size(54), 193, 242, 72, 5, 0, 12, _::binary-size(9), 0, 0, 6>>, state) do
    {state, "Heartbeat Request 3??"}
  end

  defp process_packet(_, :to_downstream, _, <<__header::binary-size(27), 71, 255, 41, 35, 71, 171, 177, 21, 72, 110, 127, 94, 69, 0, 0, 0, 0, 0, 0, 0, 0, 0, 51, 159, 196, 75, 0, 130, 194, 0, 1, 24, 0, 0, 0, 0, 0, 24>>, state) do
    {state, "Heartbeat Request 4??"}
  end

  defp process_packet(_, :to_downstream, _, <<__header::binary-size(42), 0, 32, 96, 16, 44, 143, 84, 0, 192, _::binary>>, state) do
    {state, "Heartbeat Request 5??"}
  end

  defp process_packet(_, :to_downstream, _, <<__header::binary-size(10), 24>>, state) do
    {state, "Handshake??"}
  end

  defp process_packet(_, :to_downstream, _,  <<132, 146, 126, 197, 42, 252, 117, 35, 140, 131, 164, 193, 184, 44, 96, 15>>, state) do
    {state, "Handshake 2??"}
  end

  defp process_packet(_, _, _, _, state), do: {state, false}
end
