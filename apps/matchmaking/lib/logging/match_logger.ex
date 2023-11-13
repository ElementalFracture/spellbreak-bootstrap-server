defmodule Logging.MatchLogger do
  use GenServer
  require Logger

  def start_link(%{log_directory: base_directory}, opts \\ []) do
    GenServer.start_link(__MODULE__, base_directory, opts)
  end

  @impl true
  def init(base_directory) do
    {:ok, %{
      base_directory: base_directory,
      log_file: nil
    }, {:continue, :initialize}}
  end

  def set_match_name(pid, match_name), do: GenServer.call(pid, {:set_match_name, match_name})
  def debug(pid, message), do: GenServer.cast(pid, {:log, :debug, DateTime.utc_now(), message})
  def info(pid, message), do: GenServer.cast(pid, {:log, :info, DateTime.utc_now(), message})
  def warn(pid, message), do: GenServer.cast(pid, {:log, :warning, DateTime.utc_now(), message})
  def error(pid, message), do: GenServer.cast(pid, {:log, :error, DateTime.utc_now(), message})
  def wait(pid), do: GenServer.call(pid, :wait, 6000000)

  @impl true
  def handle_continue(:initialize, state) do
    {:ok, filename, log_file} = start_new_logging("no-match", state)
    if filename, do: Logger.info("Match logging to #{filename}...")

    {:noreply, %{state | log_file: log_file}}
  end

  @impl true
  def handle_call({:set_match_name, match_name}, _, state) do
    {:ok, filename, log_file} = start_new_logging(match_name, state)
    if filename, do: Logger.info("Match logging to #{filename}...")

    {:reply, :ok, %{state | log_file: log_file}}
  end

  @impl true
  def handle_call(:wait, _, state), do: {:reply, :ok, state}

  @impl true
  def handle_cast({:log, level, ts, message}, state) do
    cond do
      state.log_file && should_log_level(level) ->
        IO.puts(state.log_file, "[#{level}] - #{DateTime.to_string(ts)} - #{message}")

      should_log_level(level) ->
        Logger.log(level, message)
    end

    {:noreply, state}
  end

  defp should_log_level(level) do
    system_level = Application.get_env(:matchmaking, :log_level)

    appropriate_levels = case system_level do
      "debug" -> [:debug, :info, :warn, :error]
      "info" -> [:info, :warn, :error]
      "warn" -> [:warn, :error]
      "none" -> []
      _ -> [:error]
    end

    Enum.member?(appropriate_levels, level)
  end

  defp start_new_logging(match_name, state) do
    %{base_directory: base_dir, log_file: log_file} = state
    if log_file, do: File.close(log_file)

    {filename, new_file} = if base_dir do
      filename = "#{base_dir}/#{match_name}.proxy_log"
      {:ok, new_file} = File.open(filename, [:append])

      {filename, new_file}
    else
      {nil, nil}
    end

    {:ok, filename, new_file}
  end
end
