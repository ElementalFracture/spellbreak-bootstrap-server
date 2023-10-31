defmodule Matchmaking.Proxy.Client do
  alias Matchmaking.Proxy.Server
  use GenServer
  require Logger

  @moduledoc """
  Routes requests/responses for a specific client through a designated port
  """

  @upstream_ip {192, 168, 86, 111}
  @upstream_port 7777
  @upstream_cutoff -1 # Used during development of proxy to get a slice of packets

  def start_link({port, downstream}) do
    GenServer.start_link(__MODULE__, {port, downstream})
  end

  @impl true
  def init({port, downstream}) do
    {:ok, socket} = :gen_udp.open(port, [:binary, active: true])
    {:ok, %{
      socket: socket,
      downstream: downstream,
      seen_upstream_responses: 0
    }}
  end

  def send_upstream(pid, data) do
    GenServer.cast(pid, {:send_upstream, data})
  end

  @impl true
  def handle_cast({:send_upstream, data}, state) do
    :ok = :gen_udp.send(state.socket, @upstream_ip, @upstream_port, data)

    {_, state} = process_data(data, state)

    {:noreply, state}
  end

  @impl true
  def handle_info({:udp, _socket, host, port, data}, state) do
    is_upstream = host == @upstream_ip && port == @upstream_port

    cond do
      is_upstream && state.seen_upstream_responses > @upstream_cutoff && @upstream_cutoff > 0 ->
        {:stop, :upstream_cutoff_reached}

        is_upstream ->
        seen_upstream_responses = state.seen_upstream_responses + 1

        {downstream_pid, client_ip, client_port} = state.downstream
        Server.send_downstream(downstream_pid, {client_ip, client_port}, data)

        {:noreply, %{ state | seen_upstream_responses: seen_upstream_responses}}

      true -> {:noreply, state}
    end
  end

  defp process_data(<<
    1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8
  >> = data, state) do
    Logger.info("Hello Message (#{client_ip_str(state)})")

  {data, state}
  end


  defp process_data(<<
    _header::binary-size(27),
    94, 142, 194, 218, 202, 94, 154, 194, 224, 230, 94,
    contents::binary
  >> = data, state) do
    [data_str | _] = :binary.split(contents, <<0>>)
    [_map_name | param_strs] = String.split(reveal_strings(data_str), "?")

    params = param_strs
    |> Enum.map(fn str -> String.split(str, "=", parts: 2) end)
    |> Map.new(fn [name, value] -> {name, value} end)
    |> update_in(["Perks"], fn val -> String.split(val, ",") |> Enum.reject(fn perk -> perk == "" end) end)
    |> update_in(["Stream"], fn val -> val == "1" end)

    Logger.info("Player (#{client_ip_str(state)}) #{inspect(params)})")

    {data, state}
  end

  defp process_data(<<
      _header::binary-size(10),
      _remaining::binary
    >> = data, state) do
    {data, state}
  end

  defp client_ip_str(state) do
      {_, client_ip, _} = state.downstream

      client_ip
      |> Tuple.to_list()
      |> Enum.join(".")
  end

  def as_base_2(binary) do
    for(<<x::size(1) <- binary>>, do: "#{x}")
    |> Enum.chunk_every(8)
    |> Enum.join(" ")
  end

  def reveal_strings(binary) do
    binary
    |> :binary.bin_to_list()
    |> Enum.map(fn x -> trunc(x/2) end)
    |> List.to_string()
  end

  def string_to_2x_binary(binary) do
    binary
    |> :binary.bin_to_list()
    |> Enum.map(fn x -> trunc(x*2) end)
    |> :binary.list_to_bin()
  end

  # defp parse_packet_idx(<<
  #   packet_idx_1::2-unsigned,
  #   packet_idx_2::6-unsigned,
  #   packet_idx_3::8-unsigned,
  #   packet_idx_4::4-unsigned,
  #   packet_idx_5::4-unsigned,
  #   packet_idx_6::8-unsigned-little,
  #   packet_state_1::8-unsigned-little,
  #   packet_state_2::8-unsigned-little,
  #   packet_state_3::8-unsigned-little,
  #   packet_state_4::10-unsigned-little,
  #   something::6-unsigned-little
  # >>) do
  #   {
  #     {packet_idx_1, packet_idx_2, packet_idx_3, packet_idx_4, packet_idx_5, packet_idx_6},
  #     {packet_state_1, packet_state_2, packet_state_3, packet_state_4},
  #     something
  #   }
  # end
end
