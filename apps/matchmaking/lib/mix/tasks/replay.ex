defmodule Mix.Tasks.Replay do
  use Mix.Task
  alias Parsing.MatchParser
  alias Matchmaking.Proxy.Utility

  def run([replay_filename | rest]) do
    {:ok, match_parser} = GenServer.start_link(MatchParser, :ok)

    File.stream!(replay_filename)
    |> Stream.map(&String.trim/1)
    |> Stream.with_index
    |> Stream.map(fn ({line, _index}) ->
      [[_, ts, server, direction, client, data, comment]] = Regex.scan(~r/^(.+?) - (.+?) ([\<\>]) ([0-9\.]+:[0-9]+):(.+) ---# (.+?) #---$/, line)
      data = String.replace(data, "--newline--", "\n")

      dir = if direction == "<", do: :to_upstream, else: :to_downstream

      source = if dir == :to_upstream, do: client, else: server
      dest = if dir == :to_upstream, do: server, else: client

      if Enum.member?(rest, "--translate") do
        convert_text = Enum.member?(rest, "--reveal-strings")
        comment = if convert_text, do: "#{comment || "???"} - #{Utility.reveal_strings(data)}", else: "#{comment || "???"}"

        cond do
          dir == :to_upstream && Enum.member?(rest, "--only-downstream") -> :noop
          dir == :to_downstream && Enum.member?(rest, "--only-upstream") -> :noop
          (comment =~ "Heartbeat" || comment =~ "Handshake") && Enum.member?(rest, "--no-heartbeat") -> :noop

          true ->
            IO.puts("#{ts} - #{server} #{direction} #{client}: #{Base.encode16(data)} ---# #{comment} #---")
        end
      else
        MatchParser.parse(match_parser, [source, dest], DateTime.from_iso8601(ts), dir, {parse_ip_port(source), parse_ip_port(dest)}, data)
      end
    end)
    |> Stream.run

    MatchParser.wait(match_parser)
  end

  defp parse_ip_port(host_str) do
    [ip, port] = host_str |> String.split(":")

    ip = ip |> String.split(".") |> Enum.map(&String.to_integer/1) |> List.to_tuple()
    port = port |> String.to_integer()

    {ip, port}
  end
end
