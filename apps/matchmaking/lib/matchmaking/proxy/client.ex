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

  @base_player_blob_bytes 206
  @player_blob_special_bytes_start 129
  @gauntlet_bytes %{
    6 => :pyro,
    0 => :stone,
    8 => :conduit,
    10 => :toxic,
    134 => :frostborn,
    200 => :tempest
  }

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

  # defp process_data(<<
  #   _packet_idx::binary-size(2),
  #   _something_1::binary-size(3),
  #   _pretty_static_1::binary-size(6),
  #   _something_2::binary-size(5),
  #   _pretty_static_2::binary-size(7),
  #   maybe_player_blob_size::size(8),
  #   _pretty_static_3::binary-size(34),
  #   remaining::binary>> = data, state) do

  #   {_, client_ip, _} = state.downstream

  #   player_name_length = trunc((maybe_player_blob_size - 150) / 2)

  #   if player_name_length > 0 && byte_size(remaining) > player_name_length do
  #     <<player_name_bytes::binary-size(player_name_length), _::binary>> = remaining

  #     player_name = player_name_bytes
  #     |> :binary.bin_to_list()
  #     |> Enum.map(&(trunc(&1 / 2)))
  #     |> List.to_string()

  #     client_ip_str = client_ip
  #     |> Tuple.to_list()
  #     |> Enum.join(".")

  #     if String.match?(player_name, ~r/^[a-zA-Z0-9\_\-]+$/) do
  #       Logger.info("#{player_name} joined the server (#{client_ip_str})")

  #       Logger.info("join-packet: #{inspect(data, limit: :infinity)}")
  #     end
  #   end

  #   {data, state}
  # end

  defp process_data(<<
    1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8
  >> = data, state) do
    Logger.info("Hello Message (#{client_ip_str(state)})")

  {data, state}
  end

  # defp process_data(<<
  #     packet_idx_1::16-unsigned-big,
  #     packet_idx_2::16-unsigned-big,
  #     packet_idx_3::32-unsigned-big,
  #     remaining::binary
  #   >> = data, state) do
  #   Logger.info("client (#{packet_idx_1}, #{packet_idx_2}, #{packet_idx_3}): #{inspect({something, some_counter, remaining}, limit: :infinity)}")

  #   {data, state}
  # end

  # defp process_data(<<
  #   _header::binary-size(10),
  #   0::8,
  #   something::binary-size(2),
  #   remaining::binary
  # >> = data, state) do
  # Logger.info("possible-client: #{inspect(remaining, limit: :infinity)}")
  # Logger.info("#{as_base_2(remaining)}")

  # {data, state}
  # end

  defp process_data(<<
      _header::binary-size(10),
      remaining::binary
    >> = data, state) do

    is_player_blob = if byte_size(remaining) > 13 do
      <<_::binary-size(13), num_bytes_of_something::8-unsigned, _::binary>> = remaining
      num_bytes_of_something = (num_bytes_of_something / 2)

      trunc(num_bytes_of_something + @base_player_blob_bytes) == byte_size(remaining)
    else
      false
    end


    if is_player_blob || data =~ <<194, 194, 194>> do
      Logger.info("client: #{inspect(remaining, limit: :infinity)}")
      Logger.info("#{as_base_2(remaining)}")

      <<_::binary-size(13), num_bytes_of_something::8-unsigned, _::binary>> = remaining
      num_bytes_of_something = (num_bytes_of_something / 2)
      # <<_::binary-size(@player_blob_special_bytes_start-1), special_bytes::binary-size(num_bytes_of_something), _::binary>> = remaining

      <<header::binary-size(48), contents::binary>> = remaining
      name = contents
      |> :binary.split(<<0b01111110>>)
      |> List.first()
      |> :binary.bin_to_list()
      |> Enum.map(fn x -> trunc(x / 2) end)
      |> :binary.list_to_bin()

      Logger.info("Special bytes: #{num_bytes_of_something}, #{name}")
    end

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
