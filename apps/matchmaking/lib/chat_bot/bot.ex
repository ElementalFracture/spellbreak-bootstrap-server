defmodule ChatBot.Bot do
  use WebSockex
  import Bitwise
  require Logger
  alias ChatBot.Activities
  alias Matchmaking.Proxy.MatchManager
  alias Matchmaking.Proxy.BanHandler
  alias ChatBot.Messages

  @admin_guild_ids [
    1169491952543223870,
    1023813169124221009
  ]

  @slash_command_ban          "sbcban"
  @slash_command_unban        "sbcunban"
  @slash_command_restart      "sbcrestart"

  # https://discord.com/developers/docs/topics/opcodes-and-status-codes
  @opcode_dispatch              0
  @opcode_heartbeat             1
  @opcode_identify              2
  @opcode_status_update         3
  @opcode_voice_state_update    4
  @opcode_voice_server_ping     5
  @opcode_resume                6
  @opcode_reconnect             7
  @opcode_request_guild_members 8
  @opcode_invalid_session       9
  @opcode_hello                 10
  @opcode_heartbeat_ack         11

  @opcodes %{
    :dispatch               => @opcode_dispatch,
    :heartbeat              => @opcode_heartbeat,
    :identify               => @opcode_identify,
    :status_update          => @opcode_status_update,
    :voice_state_update     => @opcode_voice_state_update,
    :voice_server_ping      => @opcode_voice_server_ping,
    :resume                 => @opcode_resume,
    :reconnect              => @opcode_reconnect,
    :request_guild_members  => @opcode_request_guild_members,
    :invalid_session        => @opcode_invalid_session,
    :hello                  => @opcode_hello,
    :heartbeat_ack          => @opcode_heartbeat_ack
  }

  @close_unknown_error          4000
  @close_unknown_opcode         4001
  @close_decode_error           4002
  @close_not_authenticated      4003
  @close_authentication_failed  4004
  @close_already_authenticated  4005
  @close_invalid_seq            4007
  @close_rate_limited           4008
  @close_session_timed_out      4009
  @close_invalid_shard          4010
  @close_sharding_required      4011
  @close_invalid_api_version    4012
  @close_invalid_intents        4013
  @close_disallowed_intents     4014
  @close_codes %{
    :unknown_error          => @close_unknown_error,
    :unknown_opcode         => @close_unknown_opcode,
    :decode_error           => @close_decode_error,
    :not_authenticated      => @close_not_authenticated,
    :authentication_failed  => @close_authentication_failed,
    :already_authenticated  => @close_already_authenticated,
    :invalid_seq            => @close_invalid_seq,
    :rate_limited           => @close_rate_limited,
    :session_timed_out      => @close_session_timed_out,
    :invalid_shard          => @close_invalid_shard,
    :sharding_required      => @close_sharding_required,
    :invalid_api_version    => @close_invalid_api_version,
    :invalid_intents        => @close_invalid_intents,
    :disallowed_intents     => @close_disallowed_intents,
  }

  # https://discord.com/developers/docs/topics/gateway#gateway-intents
  @intent_guilds                    1 <<< 0
  @intent_guild_members             1 <<< 1
  @intent_guild_moderation          1 <<< 2
  @intent_guild_emojis_stickers     1 <<< 3
  @intent_guild_integrations        1 <<< 4
  @intent_guild_webhooks            1 <<< 5
  @intent_guild_invites             1 <<< 6
  @intent_guild_voice_states        1 <<< 7
  @intent_guild_presences           1 <<< 8
  @intent_guild_messages            1 <<< 9
  @intent_guild_message_reactions   1 <<< 10
  @intent_guild_message_typing      1 <<< 11
  @intent_direct_messages           1 <<< 12
  @intent_direct_message_reactions  1 <<< 13
  @intent_direct_message_typing     1 <<< 14
  @intent_message_content           1 <<< 15
  @intent_guild_scheduled_events    1 <<< 16
  @intent_guild_moderation_config   1 <<< 20
  @intent_guild_moderation_exec     1 <<< 21

  @requested_intents [
    @intent_guild_messages,
    @intent_direct_messages,
    @intent_message_content,
    @intent_direct_message_reactions
  ] |> Enum.sum()

  @app_command_chat_input                     1
  @app_command_user                           2
  @app_command_message                        3

  @interact_resp_pong                         1
  @interact_resp_channel_msg                  4
  @interact_resp_deferred_channel_msg         5
  @interact_resp_deferred_update_msg          6
  @interact_resp_update_msg                   7
  @interact_resp_app_cmd_autocomplete_result  8
  @interact_resp_modal                        9
  @interact_resp_premium_required             10

  @msg_flag_crossposted                       1 <<< 0
  @msg_flag_is_crosspost                      1 <<< 1
  @msg_flag_suppress_embeds                   1 <<< 2
  @msg_flag_source_msg_deleted                1 <<< 3
  @msg_flag_urgent                            1 <<< 4
  @msg_flag_has_thread                        1 <<< 5
  @msg_flag_ephemeral                         1 <<< 6
  @msg_flag_loading                           1 <<< 7
  @msg_flag_failed_to_mention_roles_thread    1 <<< 8
  @msg_flag_suppress_notifs                   1 <<< 12
  @msg_flag_is_voice_message                  1 <<< 13

  def start_link(:ok, opts \\ []) do
    websocket_url = Req.get!("https://discordapp.com/api/gateway").body["url"]
    {:ok, client} = WebSockex.start_link("#{websocket_url}/?v=10&encoding=etf", __MODULE__, %{
      sequence_number: nil,
      heartbeat_interval: nil,
      resume_url: nil,
      session_id: nil,
      last_heartbeat: nil,
      last_heartbeat_ack: nil,
      interaction_states: %{}
    }, opts)

    {:ok, client}
  end

  def identify(pid), do: WebSockex.cast(pid, :identify)
  def resume(pid, state), do: WebSockex.cast(pid, {:resume, state.session_id, state.sequence_number})
  def set_current_status(pid, status), do: WebSockex.cast(pid, {:set_current_status, status})
  def create_global_app_commands(pid), do: WebSockex.cast(pid, :create_global_app_commands)

  @impl true
  def handle_connect(_, state) do
    if state.session_id != nil do
      resume(self(), state)
    else
      identify(self())
    end

    {:ok, %{state |
      last_heartbeat: nil,
      last_heartbeat_ack: nil,
      sequence_number: nil
    }}
  end

  @impl true
  def handle_frame({:binary, msg}, state) do
    frame = :erlang.binary_to_term(msg)

    op = @opcodes
    |> Enum.find(fn {_, val} -> val == frame.op end)
    |> elem(0)

    case process_frame(op, frame.t, frame.d, frame.s, state) do
      {:ok, state} ->
        state = if frame.s != nil, do: %{state | sequence_number: frame.s}, else: state
        {:ok, state}

      resp -> resp
    end
  end

  defp process_frame(:invalid_session, _, _, _, state) do
    Logger.debug("Invalid Session - Reconnecting...")
    {:close, %{state | session_id: nil}}
  end

  defp process_frame(:reconnect, _, _, _, state) do
    Logger.debug("Received Reconnect message")
    {:close, state}
  end

  defp process_frame(:heartbeat, _, data, _, state) do
    Logger.debug("Received Heartbeat message (Data: #{inspect(data)})")
    WebSockex.cast(self(), :heartbeat)

    {:ok, state}
  end

  # Received: Hello message
  defp process_frame(:hello, _, data, _, state) do
    Logger.debug("Received Hello message (Heartbeat interval: #{data.heartbeat_interval}, data: #{inspect(data)})")

    jitter = :rand.uniform()
    Process.send_after(self(), :send_heartbeat, floor(data.heartbeat_interval * jitter))

    {:ok, %{state | heartbeat_interval: data.heartbeat_interval}}
  end

  # Received: Dispatch message
  defp process_frame(:dispatch, :READY, data, _, state) do
    Logger.info("Discord Bot '#{data.user.username}' is READY")

    # create_global_app_commands(self())

    Process.send_after(self(), :update_status, 5 * 60_000)

    {:ok, %{state |
      resume_url: data.resume_gateway_url,
      session_id: data.session_id
    }}
  end

  defp process_frame(:dispatch, :RESUMED, _, _, state) do
    Logger.info("Discord Bot successfully resumed and is READY")

    {:ok, state}
  end

  defp process_frame(:dispatch, :MESSAGE_CREATE, data, _, state) do
    author = data["author"]["global_name"]

    Logger.info("'#{author}' posted: #{data["content"]}")
    {:ok, state}
  end

  defp process_frame(:dispatch, :INTERACTION_CREATE, interaction, _, state) do
    user = interaction["member"]["user"]["global_name"]
    in_response_to = interaction["message"]["interaction"]["name"]
    action_name = interaction["data"]["name"] || "followup"
    guild_id = interaction["guild_id"]

    msg_interact_id = interaction["message"]["interaction"]["id"]
    is_admin = Enum.member?(@admin_guild_ids, guild_id)

    Logger.debug("Responding to '#{action_name} - #{in_response_to}' for '#{user}' in guild '#{guild_id}'")

    case {is_admin, in_response_to, interaction["data"]} do
      {true, nil, %{"name" => @slash_command_restart}} ->
        respond_to_interaction(interaction, %{
          type: @interact_resp_channel_msg,
          data: Messages.server_reset_message() |> Map.put(:flags, @msg_flag_ephemeral)
        })
        {:ok, state}

      {true, @slash_command_restart, %{"custom_id" => "reset_servers"}} ->
        form_state = Map.get(state.interaction_states, msg_interact_id, %{})
        servers = Map.get(form_state, "server_select", [])
        match_managers = :gproc.lookup_pids({:p, :l, MatchManager.gproc_prop})

        reset_succeeded = match_managers
        |> Enum.reduce(true, fn manager, curr_state ->
          server_name = MatchManager.server_name(manager)
          if Enum.member?(servers, "#{server_name}") do
            case MatchManager.reset_server(manager) do
              :ok -> curr_state
              {:error, _} -> false
            end
          else
            curr_state
          end
        end)

        if reset_succeeded do
          respond_to_interaction(interaction, %{
            type: @interact_resp_update_msg,
            data: Messages.did_server_reset_message(servers) |> Map.put(:flags, @msg_flag_ephemeral)
          })
        else
          respond_to_interaction(interaction, %{
            type: @interact_resp_update_msg,
            data: Messages.failed_server_reset_message(servers) |> Map.put(:flags, @msg_flag_ephemeral)
          })
        end
        {:ok, state}

      {true, nil, %{"name" => @slash_command_ban}} ->
        respond_to_interaction(interaction, %{
          type: @interact_resp_channel_msg,
          data: Messages.ban_message() |> Map.put(:flags, @msg_flag_ephemeral)
        })
        {:ok, state}

      {true, @slash_command_ban, %{"custom_id" => "start_ban"}} ->
        form_state = Map.get(state.interaction_states, msg_interact_id, %{})

        case form_state do
          %{"duration_selected" => [duration], "player_select" => player_ips} ->
            expires_at = duration
            |> String.to_integer()
            |> then(&(DateTime.add(DateTime.utc_now(), &1 * 60 * 60, :second)))

            banned_users = player_ips
            |> Enum.map(&(String.split(&1, "\t")))
            |> Enum.map(fn [username, ip] ->
              BanHandler.ban(username, ip, user, expires_at)

              username
            end)

            respond_to_interaction(interaction, %{
              type: @interact_resp_update_msg,
              data: Messages.did_ban_message(banned_users, duration)
            })

          _ -> Logger.info("'Start ban' pressed when form not filled out: #{inspect(form_state)}")
        end

        {:ok, state}

      {true, nil, %{"name" => @slash_command_unban}} ->
        respond_to_interaction(interaction, %{
          type: @interact_resp_channel_msg,
          data: Messages.unban_message() |> Map.put(:flags, @msg_flag_ephemeral)
        })

        {:ok, state}

      {true, @slash_command_unban, %{"custom_id" => "start_unban"}} ->
        form_state = Map.get(state.interaction_states, msg_interact_id, %{})

        case form_state do
          %{"player_select" => player_usernames} ->
            player_usernames
            |> Enum.each(&(BanHandler.unban(&1, user)))

            respond_to_interaction(interaction, %{
              type: @interact_resp_update_msg,
              data: Messages.did_unban_message(player_usernames)
            })

          _ -> Logger.info("'Start unban' pressed when form not filled out: #{inspect(form_state)}")
        end

        {:ok, state}

      {true, _, %{"custom_id" => input_id, "values" => values}} ->
        interact_id = interaction["message"]["interaction"]["id"]
        respond_to_interaction(interaction, %{type: @interact_resp_deferred_update_msg})

        {:ok, put_in(state, [:interaction_states, Access.key(interact_id, %{}), input_id], values)}

      _ ->
        Logger.debug("Unknown interaction received (#{action_name}): #{inspect(interaction)}")
        {:ok, state}
    end
  end

  # Received: Dispatch message
  defp process_frame(:heartbeat_ack, _, _, _, state) do
    Logger.debug("Heartbeat ACK")

    {:ok, %{state | last_heartbeat_ack: DateTime.utc_now()}}
  end

  # Received unhandled message
  defp process_frame(op, topic, data, _, state) do
    Logger.debug("Received Unhandled Message (#{op} - #{topic}) - #{inspect(data)}")
    {:ok, state}
  end

  @impl true
  def handle_cast(:reconnect, state) do
    Logger.debug("Initiating reconnect...")

    {:close, state}
  end

  @impl true
  def handle_cast(:heartbeat, state) do
    Logger.debug("Sending heartbeat (Sequence number: #{state.sequence_number})")

    {:reply, {:binary, %{
      "op" => @opcode_heartbeat,
      "d" => state.sequence_number
    } |> :erlang.term_to_binary()}, state}
  end

  @impl true
  def handle_cast({:resume, session_id, seq_num}, state) do
    Logger.debug("Sending resume message (#{session_id}, #{seq_num})")

    {:reply, {:binary, %{
      "op" => @opcode_resume,
      "d" => %{
        "token" => discord_token(),
        "session_id" => session_id,
        "seq" => seq_num
      }
    } |> :erlang.term_to_binary()}, state}
  end

  @impl true
  def handle_cast(:identify, state) do
    Logger.debug("Sending identification")

    {:reply, {:binary, %{
      "op" => @opcode_identify,
      "d" => %{
        "token" => discord_token(),
        "properties" => %{"os" => "linux", "browser" => "elixir-bot", "device" => "spellbreak-matchmaking-bot"},
        "intents" => @requested_intents,
        "presence" => %{
          "since" => nil,
          "afk" => false,
          "status" => "online",
          "activities" => Activities.servers_online()
        }
      }
    } |> :erlang.term_to_binary()}, state}
  end

  @impl true
  def handle_cast({:set_current_status, status}, state) do
    Logger.debug("Setting current status...")

    {:reply, {:binary, %{
      "op" => @opcodes.status_update,
      "d" => status
    } |> IO.inspect(label: "current_status") |> :erlang.term_to_binary()}, state}
  end

  @impl true
  def handle_disconnect(%{reason: {:remote, @close_invalid_intents, _}} = data, state) do
    Logger.warning("Disconnected from Discord (Permament): #{inspect(data.reason)}")
    {:ok, state}
  end

  @impl true
  def handle_disconnect(%{reason: reason, attempt_number: _, conn: _}, state) do
    Logger.warning("Disconnected from Discord: #{inspect(reason)} - Reconnecting...")
    {:reconnect,  state}
  end

  @impl true
  def handle_info(:update_status, state) do
    set_current_status(self(), %{
      "since" => nil,
      "status" => "online",
      "afk" => false,
      "activities" => Activities.servers_online(),
    })

    Process.send_after(self(), :update_status, 5 * 60_000)

    {:ok, state}
  end

  @impl true
  def handle_info(:send_heartbeat, state) do
    if state.last_heartbeat != nil && DateTime.diff(state.last_heartbeat, state.last_heartbeat_ack, :millisecond) >= 0 do
      Logger.warning("Didn't receive heartbeat ACK since last heartbeat - assuming zombie connection - reconnecting...")
      WebSockex.cast(self(), :reconnect)

    else
      WebSockex.cast(self(), :heartbeat)

      jitter = :rand.uniform()
      Process.send_after(self(), :send_heartbeat, floor(state.heartbeat_interval * jitter))
    end

    {:ok, %{state | last_heartbeat: DateTime.utc_now()}}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("Socket Terminating:\n#{inspect reason}\n\n#{inspect state}")
    exit(:normal)
  end

  @impl true
  def handle_cast(:create_global_app_commands, state) do
    Logger.info("Registering global Application Commands...")

    Req.post("https://discord.com/api/v10/applications/#{discord_app_id()}/commands", headers: http_auth_headers(), json: %{
      name: @slash_command_ban,
      type: @app_command_chat_input,
      description: "Ban someone who is present in an active Spellbreak game"
    })

    Process.sleep(1000)

    Req.post("https://discord.com/api/v10/applications/#{discord_app_id()}/commands", headers: http_auth_headers(), json: %{
      name: @slash_command_unban,
      type: @app_command_chat_input,
      description: "Unban someone from Spellbreak games"
    })

    Process.sleep(1000)

    Req.post("https://discord.com/api/v10/applications/#{discord_app_id()}/commands", headers: http_auth_headers(), json: %{
      name: @slash_command_restart,
      type: @app_command_chat_input,
      description: "Reset a spellbreak server"
    })

    {:ok, state}
  end

  defp send_message_ban_prompt(from_data) do
    {:ok, %{status: 200}} = Req.post("https://discord.com/api/v10/channels/#{from_data["channel_id"]}/messages", [
      headers: http_auth_headers(),
      json: Messages.ban_message()
    ])
  end

  defp respond_to_interaction(interaction, response) do
    {:ok, %{status: 204}} = Req.post("https://discord.com/api/v10/interactions/#{interaction["id"]}/#{interaction["token"]}/callback", [
      headers: http_auth_headers(),
      json: response
    ])
  end

  defp http_auth_headers, do: %{Authorization: "Bot #{discord_token()}"}
  defp discord_app_id, do: Application.fetch_env!(:matchmaking, :discord_app_id)
  defp discord_token, do: Application.fetch_env!(:matchmaking, :discord_token)
end
