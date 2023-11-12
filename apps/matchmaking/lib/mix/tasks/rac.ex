defmodule Mix.Tasks.Rac do
  use Mix.Task
  require Logger

  def run([match_name | passthrough]) do
    log_dir = "tmp/recordings/#{match_name}"
    log_filename = "#{log_dir}/packets.log"
    replay_output_file = "#{log_dir}/packets.replay"
    compare_output_file = "#{log_dir}/packets.comparison"

    {replay_output, 0} = System.cmd("mix", ["replay", log_filename, "--translate" | passthrough])
    File.write!(replay_output_file, replay_output)

    {compare_output, 0} = System.cmd("mix", ["compare", replay_output_file | passthrough])
    File.write!(compare_output_file, compare_output)

    Logger.info("Replayed and compared!")
  end
end
