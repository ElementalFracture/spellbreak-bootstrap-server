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
    _something_1::binary-size(5),
    _pretty_static_1::binary-size(6),
    _something_2::binary-size(5),
    _pretty_static_2::binary-size(7),
    maybe_player_blob_size::size(8),
    _pretty_static_3::binary-size(34),
    remaining::binary>> = data, state) do

    {_, client_ip, _} = state.downstream

    player_name_length = trunc((maybe_player_blob_size - 150) / 2)

    if player_name_length > 0 && byte_size(remaining) > player_name_length do
      <<player_name_bytes::binary-size(player_name_length), _::binary>> = remaining

      player_name = player_name_bytes
      |> :binary.bin_to_list()
      |> Enum.map(&(trunc(&1 / 2)))
      |> List.to_string()

      client_ip_str = client_ip
      |> Tuple.to_list()
      |> Enum.join(".")

      if String.match?(player_name, ~r/^[a-zA-Z0-9\_\-]+$/) do
        Logger.info("#{player_name} joined the server (#{client_ip_str})")
      end
    end

    {data, state}
  end

  defp process_data(data, state) do
    # {data, byte_size(data)}
    # |> IO.inspect(label: "sent_upstream", limit: :infinity)

    {data, state}
  end
end
