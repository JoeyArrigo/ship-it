defmodule PokerServerTest do
  use ExUnit.Case
  doctest PokerServer

  test "greets the world" do
    assert PokerServer.hello() == :world
  end
end
