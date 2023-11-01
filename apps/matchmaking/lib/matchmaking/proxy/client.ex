defmodule Matchmaking.Proxy.Client do
  alias Matchmaking.Proxy.{Server, Utility}
  use GenServer
  require Logger

  @moduledoc """
  Routes requests/responses for a specific client through a designated port
  """

  # IP address of the server (ex: {127, 0, 0, 1})
  @upstream_ip Application.compile_env(:matchmaking, :upstream_ip)

  # Port of the server (ex: 7777)
  @upstream_port Application.compile_env(:matchmaking, :upstream_port)

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

  @doc """
  Queues a packet from the client to be sent to the server
  """
  def send_upstream(pid, data) do
    GenServer.cast(pid, {:send_upstream, data})
  end

  # Handles sending a packet from a client to the server
  @impl true
  def handle_cast({:send_upstream, data}, state) do
    :ok = :gen_udp.send(state.socket, @upstream_ip, @upstream_port, data)

    {_, state} = process_data(data, state)

    {:noreply, state}
  end

  # Received a UDP packet from an outgoing UDP port (theoretically, the upstream server)
  @impl true
  def handle_info({:udp, _socket, host, port, data}, state) do
    is_upstream = host == @upstream_ip && port == @upstream_port

    cond do
      is_upstream ->
        # This is a packet from the server we expect to see. Trust it
        seen_upstream_responses = state.seen_upstream_responses + 1

        {downstream_pid, client_ip, client_port} = state.downstream
        Server.send_downstream(downstream_pid, {client_ip, client_port}, data)

        {:noreply, %{ state | seen_upstream_responses: seen_upstream_responses}}

      true ->
        # We don't know who this is a packet from. Ignore it
        {:noreply, state}
    end
  end

  # Processes a packet from a client, headed to the server
  defp process_data(<<
    1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8
  >> = data, state) do
    Logger.info("Hello Message (#{client_ip_str(state)})")
    {data, state}
  end

  defp process_data(<<
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

    Logger.info("Player (#{client_ip_str(state)}) #{inspect(params)})")

    {data, state}
  end

  defp process_data(data, state), do: {data, state}

  defp client_ip_str(state) do
      {_, client_ip, _} = state.downstream
      Utility.host_to_ip(client_ip)
  end
end
