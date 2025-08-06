defmodule PokerServer.StringBettingTest do
  use ExUnit.Case
  alias PokerServer.{BettingRound, Player}

  # Helper to create a player
  defp player(id, chips, position), do: %Player{id: id, chips: chips, position: position}

  describe "string betting prevention" do
    test "prevents multiple actions by same player in sequence" do
      players = [
        player(1, 1000, 0),  # Small blind
        player(2, 1000, 1),  # Big blind
        player(3, 1000, 2)   # UTG
      ]
      
      betting_round = BettingRound.new(players, 10, 20, :preflop)
      
      # UTG calls
      {:ok, betting_round} = BettingRound.process_action(betting_round, 3, {:call})
      
      # UTG tries to act again immediately (should fail - not their turn)
      result = BettingRound.process_action(betting_round, 3, {:raise, 40})
      assert {:error, "not your turn"} = result
    end

    test "prevents out-of-turn actions completely" do
      players = [
        player(1, 1000, 0),  # Small blind
        player(2, 1000, 1),  # Big blind
        player(3, 1000, 2)   # UTG
      ]
      
      betting_round = BettingRound.new(players, 10, 20, :preflop)
      
      # Small blind tries to act before UTG (out of turn)
      result = BettingRound.process_action(betting_round, 1, {:call})
      assert {:error, "not your turn"} = result
      
      # Big blind tries to act before UTG (out of turn)
      result = BettingRound.process_action(betting_round, 2, {:check})
      assert {:error, "not your turn"} = result
    end

    test "action state is atomic - no partial state changes on invalid actions" do
      players = [
        player(1, 1000, 0),  # Small blind
        player(2, 1000, 1),  # Big blind
        player(3, 50, 2)     # UTG with limited chips
      ]
      
      betting_round = BettingRound.new(players, 10, 20, :preflop)
      original_state = betting_round
      
      # UTG attempts invalid raise (doesn't have enough chips for minimum raise)
      result = BettingRound.process_action(betting_round, 3, {:raise, 100})
      
      # Should fail and leave state unchanged
      assert {:error, _reason} = result
      
      # Verify state is completely unchanged
      assert betting_round == original_state
    end

    test "prevents invalid action types" do
      players = [
        player(1, 1000, 0),  # Small blind
        player(2, 1000, 1),  # Big blind
        player(3, 1000, 2)   # UTG
      ]
      
      betting_round = BettingRound.new(players, 10, 20, :preflop)
      
      # UTG tries invalid action type (check when there's a bet to call)
      result = BettingRound.process_action(betting_round, 3, {:check})
      assert {:error, "invalid action"} = result
      
      # UTG tries non-existent action type
      result = BettingRound.process_action(betting_round, 3, {:invalid_action})
      assert {:error, "invalid action"} = result
    end

    test "enforces single action per turn cycle" do
      players = [
        player(1, 1000, 0),  # Small blind
        player(2, 1000, 1),  # Big blind
        player(3, 1000, 2)   # UTG
      ]
      
      betting_round = BettingRound.new(players, 10, 20, :preflop)
      
      # UTG acts
      {:ok, betting_round} = BettingRound.process_action(betting_round, 3, {:call})
      
      # Now it should be small blind's turn
      active_player = BettingRound.get_active_player(betting_round)
      assert active_player.id == 1
      assert active_player.position == 0
      
      # Small blind acts
      {:ok, betting_round} = BettingRound.process_action(betting_round, 1, {:call})
      
      # Now it should be big blind's turn
      active_player = BettingRound.get_active_player(betting_round)
      assert active_player.id == 2  
      assert active_player.position == 1
    end

    test "action validation happens before state modification" do
      players = [
        player(1, 100, 0),   # Small blind with limited chips
        player(2, 1000, 1),  # Big blind
        player(3, 1000, 2)   # UTG
      ]
      
      betting_round = BettingRound.new(players, 10, 20, :preflop)
      original_pot = betting_round.pot
      original_chips = Enum.find(betting_round.players, &(&1.id == 3)).chips
      
      # UTG attempts impossible raise (more than they have)
      result = BettingRound.process_action(betting_round, 3, {:raise, 2000})
      
      # Should fail without modifying any state
      assert {:error, _reason} = result
      assert betting_round.pot == original_pot
      
      utg_player = Enum.find(betting_round.players, &(&1.id == 3))
      assert utg_player.chips == original_chips
    end
  end

end