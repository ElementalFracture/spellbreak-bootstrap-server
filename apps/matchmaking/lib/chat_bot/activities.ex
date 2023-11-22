defmodule ChatBot.Activities do
  alias Matchmaking.Proxy.MatchManager
  alias Parsing.MatchState

  def servers_online do
    match_managers = :gproc.lookup_pids({:p, :l, MatchManager.gproc_prop})
    match_states = :gproc.lookup_pids({:p, :l, MatchState.gproc_prop})

    states = match_states
    |> Enum.map(fn match_state ->
      server_name = MatchState.server_name(match_state)

      players = MatchState.players_and_ips(match_state)
      |> Enum.uniq_by(fn {_, player} -> player.username end)

      %{
        server_name: "#{server_name}",
        players: players
      }
    end)

    states
    |> Enum.sort_by(fn state -> Enum.count(state.players) end)
    |> Enum.map(fn state ->
      %{
        "name" => state.server_name,
        "type" => 4,
        "state" => "#{state.server_name} (#{Enum.count(state.players)} players)",
        "emoji" => %{"name" => "desktop"},
        "created_at" => :os.system_time(:seconds) * 1000
      }
    end)

  end
end
