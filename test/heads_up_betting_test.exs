defmodule PokerServer.HeadsUpBettingTest do
  use ExUnit.Case
  alias PokerServer.{BettingRound, Player}

  # Helper to create a player
  defp player(id, chips, position), do: %Player{id: id, chips: chips, position: position}

  describe "heads-up betting rules" do
    test "pre-flop: small blind acts first" do
      players = [
        # Small blind (button)
        player(1, 1000, 0),
        # Big blind
        player(2, 1000, 1)
      ]

      betting_round = BettingRound.new(players, 10, 20, :preflop)

      # In heads-up pre-flop, small blind should act first
      active_player = Enum.at(betting_round.players, betting_round.active_player_index)
      # Small blind player
      assert active_player.id == 1
      assert active_player.position == 0
    end

    test "big blind option to raise when action comes back" do
      players = [
        # Small blind
        player(1, 1000, 0),
        # Big blind
        player(2, 1000, 1)
      ]

      betting_round = BettingRound.new(players, 10, 20, :preflop)

      # Small blind calls
      {:ok, betting_round} = BettingRound.process_action(betting_round, 1, {:call})

      # Now it should be big blind's turn with option to raise
      active_player = Enum.at(betting_round.players, betting_round.active_player_index)
      # Big blind player
      assert active_player.id == 2

      valid_actions = BettingRound.valid_actions(betting_round)
      # Can check (no additional bet required)
      assert :check in valid_actions
      # Can raise (big blind option)
      assert :raise in valid_actions
    end

    test "post-flop: big blind acts first" do
      players = [
        # Small blind (button)
        player(1, 1000, 0),
        # Big blind
        player(2, 1000, 1)
      ]

      # Post-flop betting round
      betting_round = BettingRound.new(players, 10, 20, :flop)

      # In heads-up post-flop, big blind should act first
      active_player = Enum.at(betting_round.players, betting_round.active_player_index)
      # Big blind player
      assert active_player.id == 2
      assert active_player.position == 1
    end

    test "betting completes correctly in heads-up" do
      players = [
        # Small blind
        player(1, 1000, 0),
        # Big blind
        player(2, 1000, 1)
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
        # Small blind
        player(1, 1000, 0),
        # Big blind
        player(2, 1000, 1)
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
        # Small blind with limited chips
        player(1, 50, 0),
        # Big blind with many chips
        player(2, 1000, 1)
      ]

      betting_round = BettingRound.new(players, 10, 20, :preflop)

      # Small blind goes all-in
      {:ok, betting_round} = BettingRound.process_action(betting_round, 1, {:all_in})

      # Big blind calls the all-in (needs to call additional 30 chips: 50 - 20 = 30)
      {:ok, betting_round} = BettingRound.process_action(betting_round, 2, {:call})

      side_pots = BettingRound.side_pots(betting_round)

      # Should have one pot since both players bet the same amount (50 each)
      assert length(side_pots) == 1
      [main_pot] = side_pots

      # Main pot: both players contributed 50 each, total 100
      assert main_pot.eligible_players == MapSet.new([1, 2])
      assert main_pot.amount == 100
    end

    test "button rotation: lower position is small blind" do
      # Test hand 1: Player at position 0 is button/small blind
      players_hand1 = [
        # Button/Small blind
        player("alice", 1000, 0),
        # Big blind
        player("bob", 1000, 1)
      ]

      betting_round1 = BettingRound.new(players_hand1, 10, 20, :preflop)

      # Alice (position 0) should have posted small blind
      assert betting_round1.player_bets["alice"] == 10
      # Bob (position 1) should have posted big blind  
      assert betting_round1.player_bets["bob"] == 20

      # Test hand 2: After button rotation, player at lower position is still button/small blind
      players_hand2 = [
        # Big blind now
        player("alice", 1000, 1),
        # Button/Small blind now
        player("bob", 1000, 0)
      ]

      betting_round2 = BettingRound.new(players_hand2, 10, 20, :preflop)

      # Bob (position 0) should have posted small blind
      assert betting_round2.player_bets["bob"] == 10
      # Alice (position 1) should have posted big blind
      assert betting_round2.player_bets["alice"] == 20
    end
  end
end
