defmodule ChatBot.Bot do
  use WebSockex
  import Bitwise
  require Logger

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

  def start_link(:ok, opts \\ []) do
    websocket_url = Req.get!("https://discordapp.com/api/gateway").body["url"]
    {:ok, client} = WebSockex.start_link("#{websocket_url}/?v=10&encoding=etf", __MODULE__, %{
      sequence_number: nil,
      heartbeat_interval: nil,
      resume_url: nil,
      session_id: nil,
      last_heartbeat: nil,
      last_heartbeat_ack: nil
    }, opts)

    {:ok, client}
  end

  def identify(pid), do: WebSockex.cast(pid, :identify)
  def resume(pid, state), do: WebSockex.cast(pid, {:resume, state.session_id, state.sequence_number})

  @impl true
  def handle_connect(_, state) do
    if state.session_id != nil do
      resume(self(), state)
    else
      identify(self())
    end


    {:ok, %{state | last_heartbeat: nil, last_heartbeat_ack: nil, sequence_number: nil}}
  end

  @impl true
  def handle_frame({:binary, msg}, state) do
    frame = :erlang.binary_to_term(msg)

    op = @opcodes
    |> Enum.find(fn {key, val} -> val == frame.op end)
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
  defp process_frame(:hello, _, data, seq_num, state) do
    Logger.debug("Received Hello message (Heartbeat interval: #{data.heartbeat_interval}, data: #{inspect(data)})")

    jitter = :rand.uniform()
    Process.send_after(self(), :send_heartbeat, floor(data.heartbeat_interval * jitter))

    {:ok, %{state | heartbeat_interval: data.heartbeat_interval}}
  end

  # Received: Dispatch message
  defp process_frame(:dispatch, :READY, data, seq_num, state) do
    Logger.info("Discord Bot '#{data.user.username}' is READY")

    {:ok, %{state |
      resume_url: data.resume_gateway_url,
      session_id: data.session_id
    }}
  end
  defp process_frame(:dispatch, :RESUMED, data, seq_num, state) do
    Logger.info("Discord Bot successfully resumed and is READY")

    {:ok, state}
  end

  defp process_frame(:dispatch, :MESSAGE_CREATE, data, _, state) do
    author = data["author"]["global_name"]

    Logger.info("'#{author}' posted: #{data["content"]}")
    respond_to_message(author, data["content"], data, state)
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

  def handle_cast(:identify, state) do
    Logger.debug("Sending identification")

    {:reply, {:binary, %{
      "op" => @opcode_identify,
      "d" => %{
        "token" => discord_token(),
        "properties" => %{"os" => "linux", "browser" => "elixir-bot", "device" => "spellbreak-matchmaking-bot"},
        "intents" => @requested_intents,
        "presence" => %{
          "since" => DateTime.utc_now() |> DateTime.to_unix,
          "afk" => false
        }
      }
    } |> :erlang.term_to_binary()}, state}
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


  # Message handling
  defp respond_to_message(author, message, data, state) do
    is_admin = Enum.member?(discord_admins(), author)

    cond do
      is_admin && String.contains?(message, "I want to ban someone") ->
        {:ok, %{status: 200}} = Req.post("https://discord.com/api/v10/channels/#{data["channel_id"]}/messages", headers: %{Authorization: "Bot #{discord_token()}"}, json: %{
          content: "Who should be banned and for how long?",
          components: [
            %{
              type: 1,
              components: [
              %{
                type: 3,
                custom_id: "player_select",
                options: [
                  %{label: "polymorfiq", value: "polymorfiq"},
                  %{label: "Doobs", value: "Doobs"},
                  %{label: "CaptainKnife42", value: "CaptainKnife42"},
                ],
                placeholder: "Choose player(s)",
                min_values: 1,
                max_values: 3
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
        })

      true -> :ok
    end

    {:ok, state}
  end


  defp discord_token, do: Application.fetch_env!(:matchmaking, :discord_token)
  defp discord_admins, do: Application.fetch_env!(:matchmaking, :discord_admins)
end
