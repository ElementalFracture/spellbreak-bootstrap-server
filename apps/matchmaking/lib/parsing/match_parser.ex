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

  def match_state(pid) do
    GenServer.call(pid, :match_state)
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
  def handle_call(:match_state, _, state) do
    {:reply, state.match_state, state}
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

  defp process_packet(conn, :to_upstream, _,  <<_::binary-size(31), 0x61, 0x00, 0x87, 0x60, 0xBE, 0x80, 0x74, 0x59, _::binary-size(27), 0x00, 0x00, 0x0C>>, state) do
    player_info = MatchState.get_player_info(state.match_state, conn)
    player_name = Map.get(player_info, :username, "Unknown player")
    Logger.info("'SpawnMatchBot' executed by '#{player_name}'")

    {state, "SpawnMatchBot??"}
  end

  # defp process_packet(conn, :to_upstream, _, <<__header::binary-size(13), 0xF3, data::binary>>, state) do
  #   player_info = MatchState.get_player_info(state.match_state, conn)
  #   player_name = Map.get(player_info, :username, "Unknown player")

  #   cond do
  #     # match?([_, _ | _], String.split(data, <<0x71, 0x58, 0x31>>)) ->
  #     #   [_, <<map_number::unsigned-size(16), _::binary>> | _] = String.split(data, <<0x71, 0x58, 0x31>>)
  #     #     # Dominion Host
  #     #     map = case map_number do
  #     #       0x4242 -> "Hymnwood"
  #     #       0x2242 -> "Halcyon"
  #     #       0x0242 -> "Dustpool"
  #     #       0xE241 -> "Bogmore"
  #     #       0xC241 -> "Banehelm"
  #     #       _ -> "???"
  #     #     end

  #     #     [_, <<max_score_base::unsigned-little-size(32), _::binary>> | _] = String.split(data, <<0x57, 0x81, 0x8A, 0xC9, 0x0A>>)
  #     #     max_score = trunc((max_score_base - 5)/8)

  #     #     [_, <<max_score_pp_base::unsigned-little-size(32), _::binary>> | _] = String.split(data, <<0x50, 0x6C, 0x56>>)
  #     #     max_score_pp = trunc(max_score_pp_base/64)

  #     #     Logger.info("#{player_name} selected Dominion - #{map}, Max Score: #{max_score}, Max Score (Per-Player): #{max_score_pp}")

  #     #     {state, "Selected Game - Dominion - Map: #{map}, Max Score: #{max_score}, Max Score (Per-Player): #{max_score_pp}"}

  #     # true ->
  #     #   Logger.info("#{player_name} selected Battle Royale")
  #     #   {state, "Selected Game - Battle Royale"}

  #     true ->
  #       {state, "Selected Game - ???"}
  #   end
  # end

  defp process_packet(_, :to_upstream, _, <<__header::binary-size(13), 0x4B, _::binary>>, state) do
    {state, "Movement: Walking??"}
  end

  defp process_packet(_, :to_upstream, _, <<__header::binary-size(13), 0x77, _::binary>>, state) do
    {state, "Movement: Stopping??"}
  end

  defp process_packet(_, :to_upstream, _, <<__header::binary-size(13), 0x09, _::binary>>, state) do
    {state, "Movement: Vertical??"}
  end

  defp process_packet(_, :to_upstream, _, <<__header::binary-size(13), 0x5B, _::binary>>, state) do
    {state, "Movement: Vertical???"}
  end

  defp process_packet(conn, :to_upstream, _,  <<
    _::binary-size(9),
    0x20, 0x01,
    _::binary-size(2),
    rest::binary>>,
  state) do
    start_byte = find_start_byte(rest, 0)

    if start_byte != nil do
      case String.split(String.slice(rest, start_byte..-1), <<0x80, 0x01, 0x1C, 0x82, 0xF9, 0x02, 0xD2, 0x65, 0x81>>) do
        [chunk_1, _] ->
          chunk_1 = String.slice(chunk_1, 0..-2)
          player_info = MatchState.get_player_info(state.match_state, conn)
          player_name = Map.get(player_info, :username, "Unknown player")
          Logger.info("'ServerCall '#{parse_server_call_str(chunk_1)}' executed by '#{player_name}'?")

          {state, "ServerCall?? #{Base.encode16(chunk_1)} (#{parse_server_call_str(chunk_1)}')"}

        _ -> {state, "???"}
      end
    else
      {state, "???"}
    end
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

  defp process_packet(_, _, _, _, state), do: {state, "???"}

  defp parse_server_call_str(call_str), do: parse_server_call_str(0, "", call_str)
  defp parse_server_call_str(_, curr, <<>>), do: curr

  defp parse_server_call_str(pos, curr, <<char_data::binary-size(1), rest::binary>>) do
    <<char_num::unsigned-8>> = char_data

    char_num = if pos == 0 && char_num !== 0b01111000, do: char_num + 1, else: char_num

    char = case char_num do
      0b00000011 -> " "
      0b00000010 -> " "
      0b11111011 -> "_"
      0b01111000 -> "/"
      0b00001010 -> "A"
      0b00001001 -> "A"
      0b00001011 -> "A"
      0b00010010 -> "B"
      0b00010011 -> "B"
      0b00011010 -> "C"
      0b00011011 -> "C"
      0b00100010 -> "D"
      0b00100011 -> "D"
      0b00101010 -> "E"
      0b00101011 -> "E"
      0b00110010 -> "F"
      0b00110011 -> "F"
      0b00111010 -> "G"
      0b00111011 -> "G"
      0b01000010 -> "H"
      0b01000011 -> "H"
      0b01001010 -> "I"
      0b01001011 -> "I"
      0b01010010 -> "J"
      0b01010011 -> "J"
      0b01011010 -> "K"
      0b01011011 -> "K"
      0b01100010 -> "L"
      0b01100011 -> "L"
      0b01101010 -> "M"
      0b01101011 -> "M"
      0b01110010 -> "N"
      0b01110011 -> "N"
      0b01111010 -> "O"
      0b01111011 -> "O"
      0b10000010 -> "P"
      0b10000011 -> "P"
      0b10001010 -> "Q"
      0b10001011 -> "Q"
      0b10010010 -> "R"
      0b10010011 -> "R"
      0b10011010 -> "S"
      0b10011011 -> "S"
      0b10100010 -> "T"
      0b10100011 -> "T"
      0b10101010 -> "U"
      0b10101011 -> "U"
      0b10110010 -> "V"
      0b10110011 -> "V"
      0b10111010 -> "W"
      0b10111011 -> "W"
      0b11000010 -> "X"
      0b11000011 -> "X"
      0b11001010 -> "Y"
      0b11001011 -> "Y"
      0b11010010 -> "Z"
      0b11010011 -> "Z"
      0b10000001 -> "0"
      0b10001001 -> "1"
      0b10010001 -> "2"
      0b10011001 -> "3"
      0b10100001 -> "4"
      0b10101001 -> "5"
      0b10110001 -> "6"
      0b10111001 -> "7"
      0b11000001 -> "8"
      0b11001001 -> "9"
      _ -> "?"
    end

    next_modifier = case char_num do
      0b01111000 -> 1
      0b00000010 -> 2
      0b00000011 -> 2
      _ -> 0
    end

    rest = if rest != <<>> do
      <<next_byte::unsigned-size(8), next_rest::binary>> = rest
      <<next_byte + next_modifier, next_rest::binary>>
    else
      rest
    end

    parse_server_call_str(pos + 1, curr <> char, rest)
  end

  defp find_start_byte(<<>>, _), do: nil
  defp find_start_byte(<<0x00, 0x00, something::unsigned-size(8), _::binary>> = some_data, i) do
    if something != 0x00 do
      i + 2
    else
      <<_::binary-size(1), rest::binary>> = some_data
      find_start_byte(rest, i + 1)
    end
  end

  defp find_start_byte(some_data, i) do
    <<_::binary-size(1), rest::binary>> = some_data
    find_start_byte(rest, i + 1)
  end
end
