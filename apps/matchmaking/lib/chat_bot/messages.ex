defmodule ChatBot.Messages do
  alias Matchmaking.Proxy.MatchManager
  alias Matchmaking.Proxy.BanHandler
  alias Parsing.MatchState

  def ban_message do
    match_states = Swarm.members(MatchState.global_group)

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

  def kick_message do
    match_states = Swarm.members(MatchState.global_group)

    players_ip_pairs = match_states
    |> Enum.flat_map(&MatchState.players_and_ips/1)
    |> Enum.uniq_by(fn {_, player} -> player.username end)

    %{
      content: "Who should be kicked?",
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
            type: 2,
            label: "Kick",
            style: 1,
            custom_id: "start_kick"
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

  def did_kick_message(usernames) do
    %{
      content: "Kicked #{Enum.join(usernames, " + ")}!",
      components: []
    }
  end


  def server_reset_message do
    match_managers = Swarm.members(MatchManager.global_group)

    server_names = match_managers
    |> Enum.filter(&MatchManager.has_server_manager?/1)
    |> Enum.map(&MatchManager.server_name/1)
    |> Enum.sort()
    |> Enum.reverse()

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

  def failed_server_reset_message(servers) do
    %{
      content: "Failed to reset #{Enum.join(servers, " + ")}...",
      components: []
    }
  end


  def server_status_message do
    match_managers = Swarm.members(MatchManager.global_group)

    server_names = match_managers
    |> Enum.filter(&MatchManager.has_server_manager?/1)
    |> Enum.map(&MatchManager.server_name/1)
    |> Enum.sort()
    |> Enum.reverse()

    %{
      content: "What server status would you like?",
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
            label: "Get Statuses",
            style: 1,
            custom_id: "status_servers"
          }
        ]
      }
    ]
    }
  end

  def fetching_all_server_statuses_message do
    %{
      content: "Fetching statuses for all servers!",
      components: []
    }
  end

  def fetching_server_statuses_message(servers) do
    %{
      content: "Fetching statuses for #{Enum.join(servers, " + ")}!",
      components: []
    }
  end

  def with_embeds(embeds) do
    %{
      content: "",
      embeds: embeds,
      components: []
    }
  end

  def fetched_server_status_embed(manager, status) do
    server_name = MatchManager.server_name(manager)

    real_players = status["players"]
    |> Enum.filter(fn player -> !player["is_bot"] end)

    player_message = if Enum.count(real_players) > 0 do
      real_players
      |> Enum.map(fn player -> "**#{player["username"]}**" end)
      |> Enum.join("\n")
    else
      "No players currently in match."
    end

    %{
      type: "rich",
      title: server_name,
      description: "",
      color: 0x00ff00,
      fields: [
        %{
          name: "Match State",
          value: status["state"],
          inline: false
        },
        %{
          name: "Players (#{Enum.count(real_players)})",
          value: player_message,
          inline: true
        }
      ],
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  def fetched_server_status_failure_embed(manager) do
    server_name = MatchManager.server_name(manager)

    %{
      type: "rich",
      title: server_name,
      description: "",
      color: 0xff0000,
      fields: [
        %{
          name: "Error fetching status",
          value: "Server did not respond to status check"
        }
      ],
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end
end
