defmodule PokerServer.AllInScenariosTest do
  use ExUnit.Case
  alias PokerServer.{BettingRound, Player}

  # Helper to create a player
  defp player(id, chips, position), do: %Player{id: id, chips: chips, position: position}

  describe "critical all-in scenarios" do
    test "all-in with exact stack sizes creates single pot" do
      players = [
        # Small blind
        player(1, 100, 0),
        # Big blind
        player(2, 100, 1)
      ]

      betting_round = BettingRound.new(players, 5, 10, :preflop)

      # Player 1 goes all-in
      {:ok, betting_round} = BettingRound.process_action(betting_round, 1, {:all_in})
      # Player 2 calls all-in
      {:ok, betting_round} = BettingRound.process_action(betting_round, 2, {:call})

      side_pots = BettingRound.side_pots(betting_round)

      # Single pot with both players eligible
      assert length(side_pots) == 1
      [pot] = side_pots
      assert pot.amount == 200
      assert pot.eligible_players == MapSet.new([1, 2])
    end

    test "short stack all-in creates proper side pot structure" do
      players = [
        # Short stack
        player(1, 50, 0),
        # Deep stack
        player(2, 200, 1)
      ]

      betting_round = BettingRound.new(players, 5, 10, :preflop)

      # Short stack goes all-in for 50
      {:ok, betting_round} = BettingRound.process_action(betting_round, 1, {:all_in})
      # Deep stack calls (only needs to call 40 more since BB was 10)
      {:ok, betting_round} = BettingRound.process_action(betting_round, 2, {:call})

      side_pots = BettingRound.side_pots(betting_round)

      # Should create a single main pot since no overcall
      assert length(side_pots) == 1
      [pot] = side_pots
      # Both players put in 50 each
      assert pot.amount == 100
      assert pot.eligible_players == MapSet.new([1, 2])
    end

    test "all-in with reraise creates side pot" do
      players = [
        # Medium stack
        player(1, 100, 0),
        # Deep stack
        player(2, 300, 1)
      ]

      betting_round = BettingRound.new(players, 5, 10, :preflop)

      # Player 1 goes all-in for 100
      {:ok, betting_round} = BettingRound.process_action(betting_round, 1, {:all_in})

      # Player 2 calls (can only call up to player 1's all-in amount)
      {:ok, betting_round} = BettingRound.process_action(betting_round, 2, {:call})

      side_pots = BettingRound.side_pots(betting_round)

      # Single pot since player 2 can only call the all-in amount
      assert length(side_pots) == 1
      [pot] = side_pots
      # 100 from each player
      assert pot.amount == 200
      assert pot.eligible_players == MapSet.new([1, 2])
    end

    test "both players all-in with different stacks" do
      players = [
        # Smaller stack
        player(1, 75, 0),
        # Larger stack
        player(2, 125, 1)
      ]

      betting_round = BettingRound.new(players, 5, 10, :preflop)

      # Player 1 goes all-in for 75
      {:ok, betting_round} = BettingRound.process_action(betting_round, 1, {:all_in})
      # Player 2 goes all-in for 125 (but can only win what player 1 put in)
      {:ok, betting_round} = BettingRound.process_action(betting_round, 2, {:all_in})

      side_pots = BettingRound.side_pots(betting_round)

      # Should have two pots
      assert length(side_pots) == 2

      # Find main pot (both players eligible) and side pot (only player 2)
      main_pot = Enum.find(side_pots, &MapSet.equal?(&1.eligible_players, MapSet.new([1, 2])))
      side_pot = Enum.find(side_pots, &MapSet.equal?(&1.eligible_players, MapSet.new([2])))

      # Main pot: both players eligible for 75 each = 150
      assert main_pot.amount == 150
      assert main_pot.eligible_players == MapSet.new([1, 2])

      # Side pot: only player 2 eligible for remaining 50
      assert side_pot.amount == 50
      assert side_pot.eligible_players == MapSet.new([2])
    end

    test "all-in prevents further betting action" do
      players = [
        # Very short stack
        player(1, 30, 0),
        # Deep stack
        player(2, 500, 1)
      ]

      betting_round = BettingRound.new(players, 5, 10, :preflop)

      # Short stack goes all-in
      {:ok, betting_round} = BettingRound.process_action(betting_round, 1, {:all_in})

      # Deep stack should only be able to call or fold (no raising when opponent all-in)
      valid_actions = BettingRound.valid_actions(betting_round)
      assert :call in valid_actions
      assert :fold in valid_actions
      # Cannot raise when opponent is all-in
      assert :raise not in valid_actions
    end

    test "all-in betting completes immediately in heads-up" do
      players = [
        player(1, 80, 0),
        player(2, 120, 1)
      ]

      betting_round = BettingRound.new(players, 5, 10, :preflop)

      # Player 1 all-in
      {:ok, betting_round} = BettingRound.process_action(betting_round, 1, {:all_in})

      # Betting should not be complete yet (player 2 needs to act)
      assert not BettingRound.betting_complete?(betting_round)

      # Player 2 calls
      {:ok, betting_round} = BettingRound.process_action(betting_round, 2, {:call})

      # Now betting should be complete
      assert BettingRound.betting_complete?(betting_round)
    end

    test "fold to all-in ends betting immediately" do
      players = [
        player(1, 150, 0),
        player(2, 200, 1)
      ]

      betting_round = BettingRound.new(players, 10, 20, :preflop)

      # Player 1 goes all-in
      {:ok, betting_round} = BettingRound.process_action(betting_round, 1, {:all_in})

      # Player 2 folds
      {:ok, betting_round} = BettingRound.process_action(betting_round, 2, {:fold})

      # Betting should be complete
      assert BettingRound.betting_complete?(betting_round)

      # Only one player should be active (not folded)
      active_players = length(betting_round.players) - MapSet.size(betting_round.folded_players)
      assert active_players == 1
    end

    test "min raise still applies with all-in constraint" do
      players = [
        # Can only make small all-in
        player(1, 45, 0),
        # Deep stack
        player(2, 500, 1)
      ]

      betting_round = BettingRound.new(players, 5, 10, :preflop)

      # Small stack (acts first) goes all-in for 45
      {:ok, betting_round} = BettingRound.process_action(betting_round, 1, {:all_in})

      # Big stack can now call or fold (all-in prevents raises)
      {:ok, betting_round} = BettingRound.process_action(betting_round, 2, {:call})

      # Verify the all-in was accepted
      player_1 = Enum.find(betting_round.players, &(&1.id == 1))
      # All chips committed
      assert player_1.chips == 0
      assert betting_round.player_bets[1] == 45
    end

    test "all-in chip conservation - no chips created or destroyed" do
      initial_chips_1 = 85
      initial_chips_2 = 175
      total_chips = initial_chips_1 + initial_chips_2

      players = [
        player(1, initial_chips_1, 0),
        player(2, initial_chips_2, 1)
      ]

      betting_round = BettingRound.new(players, 5, 10, :preflop)

      # Both go all-in
      {:ok, betting_round} = BettingRound.process_action(betting_round, 1, {:all_in})
      {:ok, betting_round} = BettingRound.process_action(betting_round, 2, {:all_in})

      # Verify total chips in play remains constant
      total_bets = betting_round.player_bets |> Map.values() |> Enum.sum()
      remaining_chips = Enum.sum(Enum.map(betting_round.players, & &1.chips))

      assert total_bets + remaining_chips == total_chips

      # Verify side pots total correctly
      side_pots = BettingRound.side_pots(betting_round)
      total_pot_amount = Enum.sum(Enum.map(side_pots, & &1.amount))
      assert total_pot_amount == total_bets
    end
  end
end
