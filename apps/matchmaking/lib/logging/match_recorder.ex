defmodule Logging.MatchRecorder do
  use GenServer
  require Logger

  def start_link(base_directory: base_directory) do
    GenServer.start_link(__MODULE__, base_directory, name: __MODULE__)
  end

  @impl true
  def init(base_directory) do
    match_name = "unknown-match"

    {:ok, %{
      base_directory: base_directory,
      match_name: match_name,
      packet_file: nil
    }, {:continue, {:set_match_name, match_name}}}
  end

  @impl true
  def handle_continue({:set_match_name, match_name}, state) do
    change_match_name(match_name)

    {:noreply, state}
  end

  def change_match_name(new_match_name) do
    GenServer.cast(__MODULE__, {:change_match_name, new_match_name})
  end

  def record(%{
    state: _,
    timestamp: _,
    source: _,
    destination: _,
    direction: _,
    comment: _,
    data: _
  } = packet) do
    GenServer.cast(__MODULE__, {:record, packet})
  end

  @impl true
  def handle_cast({:change_match_name, new_match_name}, %{base_directory: base_directory, packet_file: packet_file} = state) do
    if Application.fetch_env!(:matchmaking, :recording_enabled) do
      if packet_file, do: File.close(packet_file)
      filename = "#{base_directory}/#{new_match_name}/packets.log"

      File.mkdir_p!("#{base_directory}/#{new_match_name}")
      {:ok, file} = File.open(filename, [:write])
      Logger.info("Match recording to #{filename}...")

      {:noreply, %{ state | match_name: new_match_name, packet_file: file }}
    else
      {:noreply, state}
    end
  end

  def handle_cast({:record, _}, %{packet_file: nil} = state), do: {:noreply, state}

  @impl true
  def handle_cast({:record, %{
    state: _,
    timestamp: ts,
    source: source,
    destination: destination,
    direction: direction,
    comment: comment,
    data: data
  }}, %{packet_file: packet_file} = state) do
    dir_indicator = if direction === :to_upstream, do: "<", else: ">"
    server = if direction === :to_upstream, do: destination, else: source
    client = if direction === :to_upstream, do: source, else: destination

    IO.binwrite(packet_file, "#{ts} - #{server} #{dir_indicator} #{client}:")
    IO.binwrite(packet_file, data |> String.replace("\n", "--newline--"))
    IO.binwrite(packet_file, " ---# #{comment || "???"} #---\n")

    {:noreply, state}
  end
end
