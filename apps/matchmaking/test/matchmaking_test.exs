defmodule MatchmakingTest do
  use ExUnit.Case
  doctest Matchmaking

  test "greets the world" do
    assert Matchmaking.hello() == :world
  end
end
