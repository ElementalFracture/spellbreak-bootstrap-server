defmodule MatchmakingTest do
  use ExUnit.Case
  import ExUnit.CaptureLog

  test "detects joined players" do
    assert capture_log(fn ->
      Mix.Tasks.Replay.run(["./priv/test_files/connect_disconnect.log"])
    end) =~ "Player 'polymorfiq' joined from 192.168.86.111"
  end

  test "detects disconnected players" do
    assert capture_log(fn ->
      Mix.Tasks.Replay.run(["./priv/test_files/connect_disconnect.log"])
    end) =~ "Player 'polymorfiq' disconnected from 192.168.86.111"
  end
end
