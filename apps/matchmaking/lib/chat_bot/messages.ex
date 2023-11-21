defmodule ChatBot.Messages do
  alias Matchmaking.Proxy.MatchManager
  alias Matchmaking.Proxy.BanHandler
  alias Parsing.MatchState

  def ban_message do
    match_states = :gproc.lookup_pids({:p, :l, MatchState.gproc_prop})

    players_ip_pairs = match_states
    |> Enum.flat_map(&MatchState.players_and_ips/1)
    |> Enum.uniq_by(fn {_, player} -> player.username end)

    %{
      content: "Who should be banned and for how long?",
      components: [
        %{
          type: 1,
          components: [
          %{
            type: 3,
            custom_id: "player_select",
            options: players_ip_pairs |> Enum.map(fn {ip, player} ->
              %{label: player.username, value: "#{player.username}\t#{ip}"}
            end),
            placeholder: "Choose player(s)",
            min_values: min(Enum.count(players_ip_pairs), 1),
            max_values: Enum.count(players_ip_pairs)
          }
        ]
      },

      %{
        type: 1,
        components: [
          %{
            type: 3,
            custom_id: "duration_selected",
            options: [
              %{label: "1 Hour", value: 1},
              %{label: "1 Day", value: 24},
              %{label: "1 Month", value: 24 * 30},
              %{label: "1 Year", value: 24 * 30 * 12},
              %{label: "Forever", value: 24 * 30 * 12 * 100},
            ],
            placeholder: "Choose a duration",
            min_values: 1,
            max_values: 1
          }
        ]
      },

      %{
        type: 1,
        components: [
          %{
            type: 2,
            label: "Start Ban",
            style: 1,
            custom_id: "start_ban"
          }
        ]
      }
    ]
    }
  end


  def unban_message do
    usernames = BanHandler.all_bans()
    |> Enum.map(&(&1.username))
    |> Enum.uniq()

    %{
      content: "Who should be unbanned?",
      components: [
        %{
          type: 1,
          components: [
          %{
            type: 3,
            custom_id: "player_select",
            options: usernames |> Enum.map(fn username ->
              %{label: username, value: username}
            end),
            placeholder: "Choose player(s)",
            min_values: min(Enum.count(usernames), 1),
            max_values: Enum.count(usernames)
          }
        ]
      },

      %{
        type: 1,
        components: [
          %{
            type: 2,
            label: "Unban",
            style: 1,
            custom_id: "start_unban"
          }
        ]
      }
    ]
    }
  end

  def did_ban_message(usernames, duration) do
    %{
      content: "Banned #{Enum.join(usernames, " + ")} for #{duration} hours!",
      components: []
    }
  end

  def did_unban_message(usernames) do
    %{
      content: "Unbanned #{Enum.join(usernames, " + ")}!",
      components: []
    }
  end


  def server_reset_message do
    match_managers = :gproc.lookup_pids({:p, :l, MatchManager.gproc_prop})

    server_names = match_managers
    |> Enum.map(&MatchManager.server_name/1)

    %{
      content: "Which servers should be restarted?",
      components: [
        %{
          type: 1,
          components: [
          %{
            type: 3,
            custom_id: "server_select",
            options: server_names |> Enum.map(fn server_name ->
              %{label: server_name, value: server_name}
            end),
            placeholder: "Choose server(s)",
            min_values: min(Enum.count(server_names), 1),
            max_values: Enum.count(server_names)
          }
        ]
      },
      %{
        type: 1,
        components: [
          %{
            type: 2,
            label: "Reset Servers",
            style: 1,
            custom_id: "reset_servers"
          }
        ]
      }
    ]
    }
  end

  def did_server_reset_message(servers) do
    %{
      content: "Resetting #{Enum.join(servers, " + ")}!",
      components: []
    }
  end
end
