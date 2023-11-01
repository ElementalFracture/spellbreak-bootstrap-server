defmodule Matchmaking.Proxy.Utility do

  @doc """
  Takes Elixir/Erlang's native representation of a host tuple and converts it to a string
  """
  def host_to_ip(host), do: host |> Tuple.to_list() |> Enum.join(".")

  @doc """
  Divides a bunch of bytes by 2, because Spellbreak for some reason multiplies its ASCII by 2
  """
  def reveal_strings(binary) do
    binary
    |> :binary.bin_to_list()
    |> Enum.map(fn x -> trunc(x/2) end)
    |> List.to_string()
  end

  @doc """
  Takes a binary and returns the bits encoded within it
  """
  def as_base_2(binary) do
    for(<<x::size(1) <- binary>>, do: "#{x}")
    |> Enum.chunk_every(8)
    |> Enum.join(" ")
  end
end
