defmodule Logging.MatchRecorder do
  use GenServer
  require Logger

  def start_link(%{recording_directory: base_directory}, opts \\ []) do
    GenServer.start_link(__MODULE__, base_directory, opts)
  end

  @impl true
  def init(base_directory) do
    {:ok, %{
      base_directory: base_directory,
      packet_file: nil
    }, {:continue, :initialize}}
  end

  def set_match_name(pid, new_match_name) do
    GenServer.call(pid, {:set_match_name, new_match_name})
  end

  def record(pid, %{
    state: _,
    timestamp: _,
    source: _,
    destination: _,
    direction: _,
    comment: _,
    data: _
  } = packet) do
    GenServer.cast(pid, {:record, packet})
  end

  @impl true
  def handle_continue(:initialize, state) do
    {:ok, filename, packet_file} = start_new_recording("no-match", state)
    if filename, do: Logger.info("Match recording to #{filename}...")

    {:noreply, %{state | packet_file: packet_file}}
  end

  @impl true
  def handle_call({:set_match_name, new_match_name}, _, state) do
    {:ok, filename, packet_file} = start_new_recording(new_match_name, state)
    if filename, do: Logger.info("Match recording to #{filename}...")

    {:reply, :ok, %{ state | packet_file: packet_file }}
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

  defp start_new_recording(match_name, state) do
    %{base_directory: base_dir, packet_file: packet_file} = state
    if packet_file, do: File.close(packet_file)

    {filename, new_file} = if base_dir do
      filename = "#{base_dir}/#{match_name}.recording"
      {:ok, new_file} = File.open(filename, [:append])

      {filename, new_file}
    else
      {nil, nil}
    end

    {:ok, filename, new_file}
  end
end
