defmodule Parsing.MatchState do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok)
  end

  @impl true
  def init(:ok) do
    {:ok, %{
      players: %{}
    }}
  end

  def set_player_info(pid, conn, key, value) do
    GenServer.cast(pid, {:set_player_info, conn, key, value})
  end

  def get_player_info(pid, conn) do
    GenServer.call(pid, {:get_player_info, conn})
  end

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
  def handle_call({:get_player_info, conn}, _, state) do
    {:reply, Map.get(state.players, conn, %{}), state}
  end
end
