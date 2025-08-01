defmodule PokerServerTest do
  use ExUnit.Case
  doctest PokerServer

  test "can create a game" do
    players = [{1, 1500}, {2, 1500}, {3, 1500}]
    assert {:ok, game_id} = PokerServer.create_game(players)
    assert is_binary(game_id)
    assert String.length(game_id) == 8
  end

  test "can start a hand" do
    players = [{1, 1500}, {2, 1500}, {3, 1500}]
    {:ok, game_id} = PokerServer.create_game(players)
    
    assert {:ok, state} = PokerServer.start_hand(game_id)
    assert state.phase == :preflop_betting
    assert is_map(state.betting_round)
  end

  test "returns error for non-existent game" do
    assert {:error, :game_not_found} = PokerServer.start_hand("nonexistent")
  end
end
