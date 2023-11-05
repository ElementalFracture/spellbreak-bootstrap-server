defmodule Matchmaking.DiscordBot.GatewayClient do
  use WebSockex
  require Logger

  @token Application.compile_env(:matchmaking, :discord_bot_token)

  def start_link(:ok) do
    websocket_url = Req.get!("https://discordapp.com/api/gateway").body["url"]

    {:ok, pid} = WebSockex.start_link("#{websocket_url}/?v=10&encoding=etf", __MODULE__, %{})
    # WebSockex.cast(pid, :heartbeat)
    # WebSockex.cast(pid, :identify)

    {:ok, pid}
  end

  @impl true
  def handle_frame({type, msg}, state), do: process_frame({type, :erlang.binary_to_term(msg)}, state)

  defp process_frame({:binary, %{op: 1} = data}, state) do
    Logger.info("Received Heartbeat message (Data: #{inspect(data)})")
    WebSockex.cast(self(), :heartbeat)

    {:ok, state}
  end

  # Received: Hello message
  defp process_frame({:binary, %{op: 10} = data}, state) do
    Logger.info("Received Hello message (Heartbeat interval: #{data.d.heartbeat_interval}, data: #{inspect(data)})")
    Process.send_after(self(), :send_heartbeat, data.d.heartbeat_interval)

    state = state
    |> Map.put(:sequence_number, data.s)

    {:ok, state}
  end

  # Received unhandled message
  defp process_frame({type, data}, state) do
    Logger.debug("Received Message - Type: #{inspect type} -- Message: #{inspect data}")
    {:ok, state}
  end

  @impl true
  def handle_cast(:heartbeat, state) do
    Logger.debug("Sending heartbeat (Sequence number: #{state.sequence_number})")

    {:reply, {:text, %{op: 1, d: state.sequence_number} |> Jason.encode!()}, state}
  end

  def handle_cast(:identify, state) do
    Logger.debug("Sending identification")

    {:reply, {:text, %{
      op: 2,
      token: @token,
      properties: %{os: "linux", browser: "disco", device: "disco"},
      intents: 18676665808960
    } |> Jason.encode!()}, state}
  end

  @impl true
  def handle_disconnect(_conn, state) do
    Logger.warning("Disconnected from websocket")
    {:reconnect, state}
  end

  @impl true
  def terminate(close_reason, _state) do
    Logger.warning("Websocket Closed: #{close_reason}")
  end

  @impl true
  def handle_info(:send_heartbeat, state) do
    WebSockex.cast(self(), :heartbeat)

    {:noreply, state}
  end
end
