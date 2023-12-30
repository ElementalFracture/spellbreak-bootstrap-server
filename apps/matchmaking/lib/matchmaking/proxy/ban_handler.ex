defmodule Matchmaking.Proxy.BanHandler do
  use GenServer
  require Logger
  alias Matchmaking.Proxy.Connection
  alias Matchmaking.Proxy.Utility

  @global_group :ban_handler

  def start_link(%{id: id, ban_file: ban_filename}) do
    GenServer.start_link(__MODULE__, ban_filename, name: {:via, :swarm, {:ban_handler, id}})
  end

  @impl true
  def init(ban_filename) do
    Swarm.join(@global_group, self())

    bans = if ban_filename != nil do
      Path.dirname(ban_filename) |> File.mkdir_p!()

      case File.read(ban_filename) do
        {:ok, contents} -> tsv_to_bans(contents)
        {:error, _} -> []
      end
    else
      []
    end

    {:ok, %{
      bans: bans,
      ban_filename: ban_filename
    }, {:continue, :initialize}}
  end

  @impl true
  def handle_continue(:initialize, state) do
    {:noreply, state}
  end

  def unban(username, unbanned_by) do
    Swarm.members(@global_group)
    |> Enum.each(fn handler -> GenServer.call(handler, {:unban, DateTime.utc_now(), username, unbanned_by}) end)
  end

  def ban(username, ip, banned_by, expires_at) do
    Swarm.members(@global_group)
    |> Enum.each(fn handler -> GenServer.call(handler, {:ban, DateTime.utc_now(), username, ip, banned_by, expires_at}) end)
  end

  def kick(username, ip, kicked_by) do
    Swarm.members(@global_group)
    |> Enum.each(fn handler -> GenServer.call(handler, {:kick, DateTime.utc_now(), username, ip, kicked_by}) end)
  end

  def all_bans do
    Swarm.members(@global_group)
    |> Enum.flat_map(fn handler -> GenServer.call(handler, :all_bans) end)
  end
  def is_banned?(host) do
    Swarm.members(@global_group)
    |> Enum.reduce(false, fn handler, is_banned ->
      is_banned || GenServer.call(handler, {:is_banned?, host})
    end)
  end

  @impl true
  def handle_call(:all_bans, _, state) do
    now = DateTime.utc_now()
    active_bans = state.bans
    |> Enum.filter(fn ban ->
      DateTime.diff(now, ban.ban_expires_at, :second) < 0
    end)

    {:reply, active_bans, state}
  end

  @impl true
  def handle_call({:ban, ts, username, ip, banned_by, expires_at}, _, state) do
    Logger.info("Banning #{username} at the request of #{banned_by} until #{DateTime.to_iso8601(expires_at)}")

    host = IP.from_string!(ip)
    new_ban = %{
      banned_at: ts,
      username: username,
      ip: host,
      banned_by: banned_by,
      ban_expires_at: expires_at
    }

    Swarm.members(Connection.global_group)
    |> Enum.each(fn proxy_connection ->
      Connection.close_if_host(proxy_connection, host)
    end)

    GenServer.cast(self(), :save)

    {:reply, :ok, %{state | bans: state.bans ++ [new_ban]}}
  end

  @impl true
  def handle_call({:unban, ts, username, unbanned_by}, _, state) do
    Logger.info("Unbanning #{username} at the request of #{unbanned_by}")

    bans = state.bans |> Enum.map(fn ban ->
      if ban.username == username && DateTime.diff(ts, ban.ban_expires_at, :second) < 0 do
        %{ban | ban_expires_at: ts}
      else
        ban
      end
    end)

    GenServer.cast(self(), :save)
    {:reply, :ok, %{state | bans: bans}}
  end

  @impl true
  def handle_call({:kick, _ts, username, ip, kicked_by}, _, state) do
    Logger.info("Kicking #{username} at the request of #{kicked_by}")

    host = IP.from_string!(ip)
    Swarm.members(Connection.global_group)
    |> Enum.each(fn proxy_connection ->
      Connection.close_if_host(proxy_connection, host)
    end)

    {:reply, :ok, state}
  end

  def handle_call({:is_banned?, host}, _, state) do
    now = DateTime.utc_now()
    ban_record = Enum.find(state.bans, fn ban ->
      ban.ip == host && DateTime.diff(now, ban.ban_expires_at, :second) < 0
    end)

    {:reply, ban_record != nil, state}
  end

  @impl true
  def handle_cast(:save, state) do
    tsv_contents = bans_to_tsv(state.bans)

    if state.ban_filename != nil do
      Logger.info("Saving to ban file: #{state.ban_filename}")

      File.write!(state.ban_filename, tsv_contents)
    end

    {:noreply, state}
  end

  defp tsv_to_bans(contents) do
    lines = contents
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(!String.starts_with?(&1, "#")))

    lines
    |> Enum.map(&(String.split(&1, ~r/[\s]+/)))
    |> Enum.map(fn [banned_at, username, ip, banned_by, ban_expiration] ->
      {:ok, banned_at, 0} = DateTime.from_iso8601(banned_at)
      {:ok, ban_expires_at, 0} = DateTime.from_iso8601(ban_expiration)

      %{
        banned_at: banned_at,
        username: username,
        ip: IP.from_string!(ip),
        banned_by: banned_by,
        ban_expires_at: ban_expires_at
      }
    end)
  end

  defp bans_to_tsv(bans) do
    lines = bans
    |> Enum.map(fn ban ->
      [
        DateTime.to_iso8601(ban.banned_at),
        ban.username,
        Utility.host_to_ip(ban.ip),
        ban.banned_by,
        DateTime.to_iso8601(ban.ban_expires_at)
      ]
      |> Enum.map(&(String.pad_trailing(&1, 35, " ")))
      |> Enum.join("")
    end)
    |> Enum.map(fn line -> "  #{line}" end)

    ["# #{[
      "Banned At",
      "Username",
      "IP",
      "Banned By",
      "Expires At"
    ] |> Enum.map(&(String.pad_trailing(&1, 35, " "))) |> Enum.join("")}" | lines]
    |> Enum.join("\n")
  end
end
