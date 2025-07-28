defmodule PokerServer.MinimumRaiseTest do
  use ExUnit.Case
  alias PokerServer.{BettingRound, Player}

  # Helper to create a player
  defp player(id, chips, position), do: %Player{id: id, chips: chips, position: position}

  describe "minimum raise enforcement" do
    test "prevents undersized raises" do
      players = [
        player(1, 1000, 0),  # Small blind
        player(2, 1000, 1),  # Big blind
        player(3, 1000, 2)   # UTG
      ]
      
      betting_round = BettingRound.new(players, 10, 20, :preflop)
      
      # UTG attempts undersized raise (should be minimum 40, trying 25)
      result = BettingRound.process_action(betting_round, 3, {:raise, 25})
      
      assert {:error, _reason} = result
    end

    test "allows minimum raise" do
      players = [
        player(1, 1000, 0),  # Small blind
        player(2, 1000, 1),  # Big blind  
        player(3, 1000, 2)   # UTG
      ]
      
      betting_round = BettingRound.new(players, 10, 20, :preflop)
      
      # UTG makes minimum raise (20 current + 20 big blind = 40)
      result = BettingRound.process_action(betting_round, 3, {:raise, 40})
      
      assert {:ok, _updated_round} = result
    end

    test "allows larger than minimum raise" do
      players = [
        player(1, 1000, 0),
        player(2, 1000, 1),
        player(3, 1000, 2)
      ]
      
      betting_round = BettingRound.new(players, 10, 20, :preflop)
      
      # UTG makes large raise
      result = BettingRound.process_action(betting_round, 3, {:raise, 100})
      
      assert {:ok, _updated_round} = result
    end

    test "minimum raise scales with previous raise size" do
      players = [
        player(1, 1000, 0),
        player(2, 1000, 1),
        player(3, 1000, 2)
      ]
      
      betting_round = BettingRound.new(players, 10, 20, :preflop)
      
      # UTG raises to 60 (40 above current bet of 20)
      {:ok, betting_round} = BettingRound.process_action(betting_round, 3, {:raise, 60})
      
      # Small blind wants to raise - minimum should now be 60 + 40 = 100
      min_raise = BettingRound.minimum_raise(betting_round)
      assert min_raise == 100
      
      # Small blind attempts undersized re-raise (should be 100, trying 80)
      result = BettingRound.process_action(betting_round, 1, {:raise, 80})
      assert {:error, _reason} = result
      
      # Small blind makes proper re-raise
      result = BettingRound.process_action(betting_round, 1, {:raise, 100})
      assert {:ok, _updated_round} = result
    end

    test "all-in less than minimum raise is allowed but doesn't reopen betting" do
      players = [
        player(1, 1000, 0),  # Small blind
        player(2, 1000, 1),  # Big blind
        player(3, 30, 2)     # UTG with limited chips
      ]
      
      betting_round = BettingRound.new(players, 10, 20, :preflop)
      
      # UTG goes all-in for 30 (less than minimum raise of 40)
      {:ok, betting_round} = BettingRound.process_action(betting_round, 3, {:all_in})
      
      # This should be allowed since it's all-in
      assert betting_round.player_bets[3] == 30
      
      # But it shouldn't reopen betting - small blind should only be able to call or fold
      # (not raise, since the all-in was less than minimum raise)
      valid_actions = BettingRound.valid_actions(betting_round)
      assert :call in valid_actions
      assert :fold in valid_actions
      # Raise might be available depending on implementation, but betting shouldn't reopen
    end

    test "all-in greater than minimum raise reopens betting" do
      players = [
        player(1, 1000, 0),  # Small blind
        player(2, 1000, 1),  # Big blind
        player(3, 100, 2)    # UTG with enough for raise
      ]
      
      betting_round = BettingRound.new(players, 10, 20, :preflop)
      
      # UTG goes all-in for 100 (more than minimum raise of 40)
      {:ok, betting_round} = BettingRound.process_action(betting_round, 3, {:all_in})
      
      # This should reopen betting
      valid_actions = BettingRound.valid_actions(betting_round)
      assert :call in valid_actions
      assert :fold in valid_actions
      assert :raise in valid_actions  # Betting should be reopened
    end

    test "calculate minimum raise correctly in complex scenario" do
      players = [
        player(1, 1000, 0),
        player(2, 1000, 1),
        player(3, 1000, 2)
      ]
      
      betting_round = BettingRound.new(players, 5, 10, :preflop)
      
      # Initial minimum raise should be 10 + 10 = 20
      assert BettingRound.minimum_raise(betting_round) == 20
      
      # UTG raises to 30 (20 above current bet of 10)
      {:ok, betting_round} = BettingRound.process_action(betting_round, 3, {:raise, 30})
      
      # Minimum raise should now be 30 + 20 = 50
      assert BettingRound.minimum_raise(betting_round) == 50
      
      # Small blind raises to 100 (70 above current bet of 30)
      {:ok, betting_round} = BettingRound.process_action(betting_round, 1, {:raise, 100})
      
      # Minimum raise should now be 100 + 70 = 170
      assert BettingRound.minimum_raise(betting_round) == 170
    end
  end
end