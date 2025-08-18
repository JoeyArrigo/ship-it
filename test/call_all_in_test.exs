defmodule PokerServer.CallAllInTest do
  use ExUnit.Case
  alias PokerServer.{BettingRound, Player}

  # Helper to create a player
  defp player(id, chips, position), do: %Player{id: id, chips: chips, position: position}

  describe "call action that results in all-in" do
    test "player calling all-in should be added to all_in_players" do
      players = [
        # Small blind - will go all-in first
        player(1, 50, 0),
        # Big blind - will call and also go all-in (needs exactly enough to call)
        player(2, 50, 1)
      ]

      betting_round = BettingRound.new(players, 10, 20, :preflop)

      # Player 1 goes all-in for 50 chips
      {:ok, betting_round} = BettingRound.process_action(betting_round, 1, {:all_in})
      
      # Verify player 1 is in all_in_players
      assert 1 in betting_round.all_in_players
      assert betting_round.current_bet == 50

      # Player 2 calls, which uses all their remaining chips
      {:ok, betting_round} = BettingRound.process_action(betting_round, 2, {:call})

      # Verify both players are now in all_in_players
      assert 1 in betting_round.all_in_players
      assert 2 in betting_round.all_in_players

      # Verify both players have 0 chips
      player_1 = Enum.find(betting_round.players, &(&1.id == 1))
      player_2 = Enum.find(betting_round.players, &(&1.id == 2))
      assert player_1.chips == 0
      assert player_2.chips == 0

      # Verify betting is complete (both players all-in)
      assert BettingRound.betting_complete?(betting_round)
    end

    test "player calling but not going all-in should not be added to all_in_players" do
      players = [
        # Small blind - will go all-in
        player(1, 30, 0),
        # Big blind - has enough chips to call without going all-in
        player(2, 100, 1)
      ]

      betting_round = BettingRound.new(players, 5, 10, :preflop)

      # Player 1 goes all-in for 30 chips
      {:ok, betting_round} = BettingRound.process_action(betting_round, 1, {:all_in})
      
      # Verify player 1 is in all_in_players
      assert 1 in betting_round.all_in_players
      assert betting_round.current_bet == 30

      # Player 2 calls, but doesn't go all-in (30 - 10 = 20 more chips needed)
      {:ok, betting_round} = BettingRound.process_action(betting_round, 2, {:call})

      # Verify only player 1 is in all_in_players
      assert 1 in betting_round.all_in_players
      refute 2 in betting_round.all_in_players

      # Verify chip counts
      player_1 = Enum.find(betting_round.players, &(&1.id == 1))
      player_2 = Enum.find(betting_round.players, &(&1.id == 2))
      assert player_1.chips == 0
      assert player_2.chips == 70  # 100 - 10 (BB) - 20 (call) = 70
    end

    test "multiple players can go all-in via calls" do
      players = [
        player(1, 50, 0),   # Will go all-in
        player(2, 50, 1),   # Will call all-in  
        player(3, 50, 2)    # Will call all-in
      ]

      betting_round = BettingRound.new(players, 5, 10, :preflop)

      # Get the first active player (might not be player 1)
      first_active = BettingRound.get_active_player(betting_round)
      
      # First active player goes all-in
      {:ok, betting_round} = BettingRound.process_action(betting_round, first_active.id, {:all_in})
      assert first_active.id in betting_round.all_in_players

      # Get next active player and have them call (going all-in)
      second_active = BettingRound.get_active_player(betting_round)
      {:ok, betting_round} = BettingRound.process_action(betting_round, second_active.id, {:call})
      assert second_active.id in betting_round.all_in_players

      # Get next active player and have them call (going all-in)
      third_active = BettingRound.get_active_player(betting_round)
      {:ok, betting_round} = BettingRound.process_action(betting_round, third_active.id, {:call})
      assert third_active.id in betting_round.all_in_players

      # All players should be all-in
      assert MapSet.size(betting_round.all_in_players) == 3
      assert BettingRound.betting_complete?(betting_round)
    end
  end
end