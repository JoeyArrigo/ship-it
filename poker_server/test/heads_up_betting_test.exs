defmodule PokerServer.HeadsUpBettingTest do
  use ExUnit.Case
  alias PokerServer.{BettingRound, Player}

  # Helper to create a player
  defp player(id, chips, position), do: %Player{id: id, chips: chips, position: position}

  describe "heads-up betting rules" do
    test "pre-flop: small blind acts first" do
      players = [
        player(1, 1000, 0),  # Small blind (button)
        player(2, 1000, 1)   # Big blind
      ]
      
      betting_round = BettingRound.new(players, 10, 20, :preflop)
      
      # In heads-up pre-flop, small blind should act first
      active_player = Enum.at(betting_round.players, betting_round.active_player_index)
      assert active_player.id == 1  # Small blind player
      assert active_player.position == 0
    end

    test "big blind option to raise when action comes back" do
      players = [
        player(1, 1000, 0),  # Small blind
        player(2, 1000, 1)   # Big blind
      ]
      
      betting_round = BettingRound.new(players, 10, 20, :preflop)
      
      # Small blind calls
      {:ok, betting_round} = BettingRound.process_action(betting_round, 1, {:call})
      
      # Now it should be big blind's turn with option to raise
      active_player = Enum.at(betting_round.players, betting_round.active_player_index)
      assert active_player.id == 2  # Big blind player
      
      valid_actions = BettingRound.valid_actions(betting_round)
      assert :check in valid_actions  # Can check (no additional bet required)
      assert :raise in valid_actions  # Can raise (big blind option)
    end

    test "post-flop: big blind acts first" do
      players = [
        player(1, 1000, 0),  # Small blind (button)
        player(2, 1000, 1)   # Big blind
      ]
      
      # Post-flop betting round
      betting_round = BettingRound.new(players, 10, 20, :flop)
      
      # In heads-up post-flop, big blind should act first
      active_player = Enum.at(betting_round.players, betting_round.active_player_index)
      assert active_player.id == 2  # Big blind player
      assert active_player.position == 1
    end

    test "betting completes correctly in heads-up" do
      players = [
        player(1, 1000, 0),  # Small blind
        player(2, 1000, 1)   # Big blind
      ]
      
      betting_round = BettingRound.new(players, 10, 20, :preflop)
      
      # Small blind calls
      {:ok, betting_round} = BettingRound.process_action(betting_round, 1, {:call})
      
      # Big blind checks (ending betting)
      {:ok, betting_round} = BettingRound.process_action(betting_round, 2, {:check})
      
      # Betting should be complete
      assert BettingRound.betting_complete?(betting_round)
    end

    test "big blind can raise after small blind call" do
      players = [
        player(1, 1000, 0),  # Small blind
        player(2, 1000, 1)   # Big blind
      ]
      
      betting_round = BettingRound.new(players, 10, 20, :preflop)
      
      # Small blind calls (completing the bet to 20)
      {:ok, betting_round} = BettingRound.process_action(betting_round, 1, {:call})
      
      # Big blind should have option to raise
      valid_actions = BettingRound.valid_actions(betting_round)
      assert :raise in valid_actions
      
      # Big blind raises to 40
      {:ok, betting_round} = BettingRound.process_action(betting_round, 2, {:raise, 40})
      
      # Should now be small blind's turn again
      active_player = Enum.at(betting_round.players, betting_round.active_player_index)
      assert active_player.id == 1
      
      # Small blind should be able to call or fold
      valid_actions = BettingRound.valid_actions(betting_round)
      assert :call in valid_actions
      assert :fold in valid_actions
    end

    test "heads-up side pots work correctly" do
      players = [
        player(1, 50, 0),   # Small blind with limited chips
        player(2, 1000, 1)  # Big blind with many chips
      ]
      
      betting_round = BettingRound.new(players, 10, 20, :preflop)
      
      # Small blind goes all-in
      {:ok, betting_round} = BettingRound.process_action(betting_round, 1, {:all_in})
      
      # Big blind calls
      {:ok, betting_round} = BettingRound.process_action(betting_round, 2, {:call})
      
      side_pots = BettingRound.side_pots(betting_round)
      
      # Should have one pot since both players are involved
      assert length(side_pots) == 1
      main_pot = List.first(side_pots)
      assert main_pot.eligible_players == MapSet.new([1, 2])
      # Pot should be: small blind's 40 remaining chips + big blind's call of 40 + initial blinds
      assert main_pot.amount == 100  # 50 (SB all-in) + 50 (BB call to match)
    end
  end
end