defmodule ChatBot.Activities do
  import Bitwise
  alias Matchmaking.Proxy.MatchManager
  alias Parsing.MatchState

  @activity_instance              1 <<< 0
  @activity_join                  1 <<< 1
  @activity_spectate              1 <<< 2
  @activity_join_request          1 <<< 3
  @activity_sync                  1 <<< 4
  @activity_play                  1 <<< 5
  @activity_party_privacy_friends 1 <<< 6
  @activity_party_privacy_voice   1 <<< 7
  @activity_embedded              1 <<< 8

  def servers_online do
    match_managers = Swarm.members(MatchManager.global_group)
    match_states = Swarm.members(MatchState.global_group)

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
    |> Enum.sort_by(fn state -> Enum.count(state.players) end, :desc)
    |> Enum.map(fn state ->
      %{
        "name" => state.server_name,
        "type" => 4,
        "state" => "#{state.server_name} (#{Enum.count(state.players)} players)"
      }
    end)

  end
end
