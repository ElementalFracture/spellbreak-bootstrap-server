defmodule Mix.Tasks.Compare do
  use Mix.Task

  def run([compare_filename | _]) do
    File.stream!(compare_filename)
    |> Stream.map(&String.trim/1)
    |> Stream.with_index
    |> Stream.transform(<<>>, fn ({line, _index}, prev_data) ->
      [[_, something, byte_str, something_else]] = Regex.scan(~r/^(.+?): (.+?) (.+)$/, line)

      bytes = byte_str |> String.graphemes() |> Enum.chunk_every(2)
      data = bytes |> Enum.reduce(<<>>, fn byte_hex, acc -> acc <> Base.decode16!(Enum.join(byte_hex, "")) end)

      smallest_data_len = min(byte_size(prev_data), byte_size(data))
      overlapping_byte_range = if smallest_data_len > 0, do: (0..smallest_data_len-1), else: []

      byte_comparison = overlapping_byte_range |> Enum.map(fn i ->
        <<_::binary-size(i), prev_byte::unsigned-size(8), _::binary>> = prev_data
        <<_::binary-size(i), curr_byte::unsigned-size(8), _::binary>> = data

        cond do
          prev_byte < curr_byte -> "++"
          prev_byte > curr_byte -> "--"
          true -> "=="
        end
      end)

      IO.puts("#{something}: #{byte_comparison |> Enum.join("")} #{something_else}")
      IO.puts("#{something}: #{Base.encode16(data)} #{something_else}")
      {[], data}
    end)
    |> Stream.run()
  end
end
