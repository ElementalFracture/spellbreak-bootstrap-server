defmodule Mix.Tasks.Replay do
  use Mix.Task
  alias Parsing.MatchParser
  alias Matchmaking.Proxy.Utility

  def run([replay_filename | _] = args) do
    {opts, _, _} = OptionParser.parse(args, strict: [
      translate: :boolean,
      reveal_strings: :boolean,
      only_downstream: :boolean,
      only_upstream: :boolean,
      no_heartbeat: :boolean,
      select: [:string, :keep],
    ])

    selected_strings = opts |> Keyword.get_values(:select)

    {:ok, match_parser} = GenServer.start_link(MatchParser, :ok)

    File.stream!(replay_filename)
    |> Stream.map(&String.trim/1)
    |> Stream.with_index
    |> Stream.map(fn ({line, _index}) ->
      [[_, ts, server, direction, client, data, comment]] = Regex.scan(~r/^(.+?) - (.+?) ([\<\>]) ([0-9\.]+:[0-9]+):(.+) ---# (.+?) #---$/, line)
      data = String.replace(data, "--newline--", "\n")
      data = data |> :binary.decode_unsigned(:little) |> :binary.encode_unsigned(:big)

      dir = if direction == "<", do: :to_upstream, else: :to_downstream

      source = if dir == :to_upstream, do: client, else: server
      dest = if dir == :to_upstream, do: server, else: client

      if opts[:translate] do
        convert_text = opts[:reveal_strings]
        comment = if convert_text, do: "#{comment || "???"} - #{Utility.reveal_strings(data)}", else: "#{comment || "???"}"

        not_selected = Enum.count(selected_strings) > 0 && Enum.find(selected_strings, fn selected -> String.contains?(comment, selected) || String.contains?(Base.encode16(data), selected) end) == nil

        cond do
          dir == :to_upstream && opts[:only_downstream] -> :noop
          dir == :to_downstream && opts[:only_upstream] -> :noop
          not_selected -> :noop

          (comment =~ "Heartbeat" || comment =~ "Handshake") && opts[:no_heartbeat] -> :noop

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
