defmodule Mix.Tasks.Compare do
  use Mix.Task

  def run([compare_filename | _] = args) do
    {opts, _, _} = OptionParser.parse(args, strict: [
      focus: [:string, :keep],
      focus_len: [:string, :keep],
      implied_equals: :boolean,
      implied_nonequals: :boolean,
    ])

    focused_bytes = opts |> Keyword.get_values(:focus)
    focused_lengths = opts |> Keyword.get_values(:focus_len)

    File.stream!(compare_filename)
    |> Stream.map(&String.trim/1)
    |> Stream.with_index
    |> Stream.transform(<<>>, fn ({line, _index}, prev_data) ->
      case Regex.scan(~r/^(.+?): (.+?) (.+)$/, line) do
        [[_, something, byte_str, something_else]] ->
          bytes = byte_str |> String.graphemes() |> Enum.chunk_every(2)
          data = bytes |> Enum.reduce(<<>>, fn byte_hex, acc ->

            case Base.decode16(Enum.join(byte_hex, "")) do
              {:ok, decoded} -> acc <> decoded
              _ -> acc <> "[?]"
            end
          end)

          smallest_data_len = min(byte_size(prev_data), byte_size(data))
          overlapping_byte_range = if smallest_data_len > 0, do: (0..smallest_data_len-1), else: []

          byte_comparison = overlapping_byte_range |> Enum.map(fn i ->
            <<_::binary-size(i), prev_byte::unsigned-size(8), _::binary>> = prev_data
            <<_::binary-size(i), curr_byte::unsigned-size(8), _::binary>> = data

            is_focused = Enum.reduce(focused_bytes, Enum.count(focused_bytes) == 0, fn focus_bytes, is_focused ->
              matches_focus = case Integer.parse(focus_bytes) do
                {byte_num, ""} -> (i + 1) == byte_num
                _ ->
                  {range, _} = Code.eval_string(focus_bytes)
                  Enum.member?(range, i + 1)
              end

              is_focused || matches_focus
            end)

            cond do
              !is_focused -> "  "
              prev_byte == curr_byte && !opts[:implied_equals] -> "=="
              opts[:implied_nonequals] -> "  "
              prev_byte < curr_byte -> "++"
              prev_byte > curr_byte -> "--"
              true -> "  "
            end
          end)


          is_right_len = Enum.reduce(focused_lengths, Enum.count(focused_lengths) == 0, fn focus_len, is_focused ->
            matches_focus = case Integer.parse(focus_len) do
              {byte_num, ""} -> byte_size(data) == byte_num
              _ ->
                {range, _} = Code.eval_string(focus_len)
                Enum.member?(range, byte_size(data))
            end

            is_focused || matches_focus
          end)

          cond do
            !is_right_len -> {[], prev_data}
            Enum.count(byte_comparison) > 0 ->
              IO.puts("#{something}: #{byte_comparison |> Enum.join("")} #{something_else}")
              IO.puts("#{something}: #{Base.encode16(data)} #{something_else}")
              {[], data}

            true ->
              IO.puts("#{something}: #{Base.encode16(data)} #{something_else}")
              {[], data}

          end

        _ ->
          IO.puts(line)
          {[], prev_data}

        end
    end)
    |> Stream.run()
  end
end
