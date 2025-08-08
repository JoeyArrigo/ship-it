defmodule PokerServer.BettingRoundTest do
  use ExUnit.Case
  alias PokerServer.{BettingRound, Player}

  # Helper to create a player
  defp player(id, chips, position), do: %Player{id: id, chips: chips, position: position}

  describe "new/4" do
    test "creates betting round with correct initial state" do
      players = [
        player(1, 1000, 0),
        player(2, 1000, 1),
        player(3, 1000, 2)
      ]

      betting_round = BettingRound.new(players, 10, 20, :preflop)

      assert betting_round.small_blind == 10
      assert betting_round.big_blind == 20
      assert betting_round.round_type == :preflop
      # SB + BB
      assert betting_round.pot == 30
      assert betting_round.current_bet == 20
      # UTG after blinds posted
      assert betting_round.active_player_index == 2
    end

    test "posts blinds automatically" do
      players = [
        # Small blind
        player(1, 1000, 0),
        # Big blind
        player(2, 1000, 1),
        player(3, 1000, 2)
      ]

      betting_round = BettingRound.new(players, 10, 20, :preflop)

      # Check player bets
      player_bets = betting_round.player_bets
      # Small blind
      assert player_bets[1] == 10
      # Big blind
      assert player_bets[2] == 20
      # No bet yet
      assert player_bets[3] == 0
    end

    test "adjusts player chips after posting blinds" do
      players = [
        player(1, 1000, 0),
        player(2, 1000, 1),
        player(3, 1000, 2)
      ]

      betting_round = BettingRound.new(players, 10, 20, :preflop)

      updated_players = betting_round.players
      # SB paid
      assert Enum.find(updated_players, &(&1.id == 1)).chips == 990
      # BB paid
      assert Enum.find(updated_players, &(&1.id == 2)).chips == 980
      # No change
      assert Enum.find(updated_players, &(&1.id == 3)).chips == 1000
    end
  end

  describe "valid_actions/1" do
    test "returns fold, call, raise for typical situation" do
      players = [player(1, 1000, 0), player(2, 1000, 1), player(3, 1000, 2)]
      betting_round = BettingRound.new(players, 10, 20, :preflop)

      actions = BettingRound.valid_actions(betting_round)
      assert :fold in actions
      assert :call in actions
      assert :raise in actions
    end

    test "returns fold, check when no bet to call" do
      players = [player(1, 1000, 0), player(2, 1000, 1)]

      betting_round =
        BettingRound.new(players, 10, 20, :flop)
        |> Map.put(:current_bet, 0)
        |> Map.put(:player_bets, %{1 => 0, 2 => 0})

      actions = BettingRound.valid_actions(betting_round)
      assert :fold in actions
      assert :check in actions
      assert :raise in actions
      refute :call in actions
    end

    test "includes all_in when player has insufficient chips for full raise" do
      # Player 1 has only 30 chips
      players = [player(1, 30, 0), player(2, 1000, 1)]

      betting_round =
        BettingRound.new(players, 10, 20, :preflop)
        |> Map.put(:current_bet, 100)

      actions = BettingRound.valid_actions(betting_round)
      assert :all_in in actions
    end
  end

  describe "process_action/3" do
    test "processes fold action" do
      players = [player(1, 1000, 0), player(2, 1000, 1), player(3, 1000, 2)]
      betting_round = BettingRound.new(players, 10, 20, :preflop)

      {:ok, updated_round} = BettingRound.process_action(betting_round, 3, {:fold})

      # Player 3 should be marked as folded
      folded_players = updated_round.folded_players
      assert 3 in folded_players

      # Move to next player
      assert updated_round.active_player_index != 2
    end

    test "processes call action" do
      players = [player(1, 1000, 0), player(2, 1000, 1), player(3, 1000, 2)]
      betting_round = BettingRound.new(players, 10, 20, :preflop)

      {:ok, updated_round} = BettingRound.process_action(betting_round, 3, {:call})

      # Player 3 should have called the big blind
      assert updated_round.player_bets[3] == 20
      # 10 + 20 + 20
      assert updated_round.pot == 50

      # Player 3's chips should be reduced
      player_3 = Enum.find(updated_round.players, &(&1.id == 3))
      assert player_3.chips == 980
    end

    test "processes raise action" do
      players = [player(1, 1000, 0), player(2, 1000, 1), player(3, 1000, 2)]
      betting_round = BettingRound.new(players, 10, 20, :preflop)

      {:ok, updated_round} = BettingRound.process_action(betting_round, 3, {:raise, 40})

      # Current bet should be updated
      assert updated_round.current_bet == 40
      assert updated_round.player_bets[3] == 40
      # 10 + 20 + 40
      assert updated_round.pot == 70

      # Player 3's chips should be reduced
      player_3 = Enum.find(updated_round.players, &(&1.id == 3))
      assert player_3.chips == 960
    end

    test "processes check action" do
      players = [player(1, 1000, 0), player(2, 1000, 1)]

      betting_round = %BettingRound{
        players: players,
        small_blind: 10,
        big_blind: 20,
        round_type: :flop,
        pot: 40,
        current_bet: 0,
        player_bets: %{1 => 0, 2 => 0},
        active_player_index: 0,
        folded_players: MapSet.new(),
        all_in_players: MapSet.new()
      }

      {:ok, updated_round} = BettingRound.process_action(betting_round, 1, {:check})

      # Pot and bets should remain unchanged
      assert updated_round.pot == 40
      assert updated_round.player_bets[1] == 0
      assert updated_round.active_player_index == 1
    end

    test "processes all_in action" do
      # Player 1 has only 30 chips
      players = [player(1, 30, 0), player(2, 1000, 1)]

      betting_round =
        BettingRound.new(players, 10, 20, :preflop)
        |> Map.put(:current_bet, 100)

      {:ok, updated_round} = BettingRound.process_action(betting_round, 1, {:all_in})

      # Player 1 should be all-in
      assert 1 in updated_round.all_in_players
      # All remaining chips
      assert updated_round.player_bets[1] == 30

      player_1 = Enum.find(updated_round.players, &(&1.id == 1))
      assert player_1.chips == 0
    end

    test "rejects invalid action" do
      players = [player(1, 1000, 0), player(2, 1000, 1), player(3, 1000, 2)]
      betting_round = BettingRound.new(players, 10, 20, :preflop)

      # Try to check when there's a bet to call
      result = BettingRound.process_action(betting_round, 3, {:check})
      assert {:error, _reason} = result
    end

    test "rejects action from wrong player" do
      players = [player(1, 1000, 0), player(2, 1000, 1), player(3, 1000, 2)]
      betting_round = BettingRound.new(players, 10, 20, :preflop)

      # Player 1 tries to act when it's player 3's turn
      result = BettingRound.process_action(betting_round, 1, {:call})
      assert {:error, _reason} = result
    end
  end

  describe "betting_complete?/1" do
    test "returns false when not all players have acted" do
      players = [player(1, 1000, 0), player(2, 1000, 1), player(3, 1000, 2)]
      betting_round = BettingRound.new(players, 10, 20, :preflop)

      refute BettingRound.betting_complete?(betting_round)
    end

    test "returns true when all players have called or folded" do
      players = [player(1, 1000, 0), player(2, 1000, 1), player(3, 1000, 2)]

      betting_round =
        BettingRound.new(players, 10, 20, :preflop)
        # All called
        |> Map.put(:player_bets, %{1 => 20, 2 => 20, 3 => 20})
        |> Map.put(:pot, 60)
        # No one left to act
        |> Map.put(:players_who_can_act, MapSet.new())

      assert BettingRound.betting_complete?(betting_round)
    end

    test "returns true when only one player remains (others folded)" do
      players = [player(1, 1000, 0), player(2, 1000, 1), player(3, 1000, 2)]

      betting_round =
        BettingRound.new(players, 10, 20, :preflop)
        # Two players folded
        |> Map.put(:folded_players, MapSet.new([1, 3]))

      assert BettingRound.betting_complete?(betting_round)
    end

    test "heads up preflop: small blind calls, big blind should still get option" do
      # SB=1, BB=2
      players = [player(1, 1000, 0), player(2, 1000, 1)]
      betting_round = BettingRound.new(players, 10, 20, :preflop)

      # Small blind calls
      {:ok, updated_round} = BettingRound.process_action(betting_round, 1, {:call})

      # Betting should NOT be complete - big blind should get option
      refute BettingRound.betting_complete?(updated_round)

      # Big blind should be able to check or raise
      actions = BettingRound.valid_actions(updated_round)
      assert :check in actions
      assert :raise in actions
    end

    test "heads up preflop: small blind calls, big blind checks, betting complete" do
      # SB=1, BB=2
      players = [player(1, 1000, 0), player(2, 1000, 1)]
      betting_round = BettingRound.new(players, 10, 20, :preflop)

      # Small blind calls
      {:ok, after_call} = BettingRound.process_action(betting_round, 1, {:call})

      # Big blind checks
      {:ok, after_check} = BettingRound.process_action(after_call, 2, {:check})

      # Now betting should be complete
      assert BettingRound.betting_complete?(after_check)
    end

    test "multi-player preflop: all call, betting complete" do
      players = [player(1, 1000, 0), player(2, 1000, 1), player(3, 1000, 2)]
      betting_round = BettingRound.new(players, 10, 20, :preflop)

      # UTG calls
      {:ok, after_utg_call} = BettingRound.process_action(betting_round, 3, {:call})
      refute BettingRound.betting_complete?(after_utg_call)

      # Small blind calls
      {:ok, after_sb_call} = BettingRound.process_action(after_utg_call, 1, {:call})
      refute BettingRound.betting_complete?(after_sb_call)

      # Big blind checks (everyone matched)
      {:ok, after_bb_check} = BettingRound.process_action(after_sb_call, 2, {:check})

      # Now betting should be complete
      assert BettingRound.betting_complete?(after_bb_check)
    end
  end

  describe "minimum_raise/1" do
    test "returns minimum raise amount" do
      players = [player(1, 1000, 0), player(2, 1000, 1)]
      betting_round = BettingRound.new(players, 10, 20, :preflop)

      min_raise = BettingRound.minimum_raise(betting_round)
      # Big blind * 2
      assert min_raise == 40
    end

    test "considers previous raise size" do
      players = [player(1, 1000, 0), player(2, 1000, 1)]

      betting_round =
        BettingRound.new(players, 10, 20, :preflop)
        # Someone raised to 60 (40 raise over BB)
        |> Map.put(:current_bet, 60)
        |> Map.put(:last_raise_size, 40)

      min_raise = BettingRound.minimum_raise(betting_round)
      # 60 + 40 (last raise size)
      assert min_raise == 100
    end
  end

  describe "side_pots/1" do
    test "creates side pots for all-in players" do
      players = [
        # All-in with 100 chips
        player(1, 0, 0),
        # Active with more chips
        player(2, 500, 1),
        # Active with most chips
        player(3, 1000, 2)
      ]

      betting_round = %BettingRound{
        players: players,
        player_bets: %{1 => 100, 2 => 200, 3 => 200},
        all_in_players: MapSet.new([1]),
        folded_players: MapSet.new(),
        pot: 500,
        small_blind: 10,
        big_blind: 20,
        round_type: :flop,
        current_bet: 200,
        active_player_index: 0
      }

      side_pots = BettingRound.side_pots(betting_round)

      # Should have main pot (all can win) and side pot (players 2,3 only)
      assert length(side_pots) == 2

      [main_pot, side_pot] = side_pots
      # 100 * 3
      assert main_pot.amount == 300
      assert main_pot.eligible_players == MapSet.new([1, 2, 3])

      # (200-100) * 2
      assert side_pot.amount == 200
      assert side_pot.eligible_players == MapSet.new([2, 3])
    end

    test "creates multiple side pots for complex all-in scenario" do
      # Complex scenario: 4 players with different all-in amounts
      # Player 1: 50 chips all-in
      # Player 2: 150 chips all-in
      # Player 3: 300 chips all-in
      # Player 4: 400 chips (calls 300)
      players = [
        # All-in with 50
        player(1, 0, 0),
        # All-in with 150
        player(2, 0, 1),
        # All-in with 300
        player(3, 0, 2),
        # Called 300, has 100 left
        player(4, 100, 3)
      ]

      betting_round = %BettingRound{
        players: players,
        player_bets: %{1 => 50, 2 => 150, 3 => 300, 4 => 300},
        all_in_players: MapSet.new([1, 2, 3]),
        folded_players: MapSet.new(),
        # 50 + 150 + 300 + 300
        pot: 800,
        small_blind: 10,
        big_blind: 20,
        round_type: :flop,
        current_bet: 300,
        active_player_index: 0
      }

      side_pots = BettingRound.side_pots(betting_round)

      # Should create 4 pots:
      # Main pot: 50 * 4 = 200 (all 4 players eligible)
      # Side pot 1: (150-50) * 3 = 300 (players 2,3,4 eligible)
      # Side pot 2: (300-150) * 2 = 300 (players 3,4 eligible)
      # Side pot 3: 0 (no additional chips from player 4)
      assert length(side_pots) == 3

      [main_pot, side_pot_1, side_pot_2] = side_pots

      # Main pot: Everyone can win up to smallest all-in
      assert main_pot.amount == 200
      assert main_pot.eligible_players == MapSet.new([1, 2, 3, 4])

      # Side pot 1: Players 2,3,4 can win the next layer
      assert side_pot_1.amount == 300
      assert side_pot_1.eligible_players == MapSet.new([2, 3, 4])

      # Side pot 2: Players 3,4 can win the top layer
      assert side_pot_2.amount == 300
      assert side_pot_2.eligible_players == MapSet.new([3, 4])
    end

    test "handles all players all-in with different amounts" do
      # Everyone all-in scenario
      players = [
        # All-in with 75
        player(1, 0, 0),
        # All-in with 125
        player(2, 0, 1),
        # All-in with 200
        player(3, 0, 2)
      ]

      betting_round = %BettingRound{
        players: players,
        player_bets: %{1 => 75, 2 => 125, 3 => 200},
        all_in_players: MapSet.new([1, 2, 3]),
        folded_players: MapSet.new(),
        pot: 400,
        small_blind: 10,
        big_blind: 20,
        round_type: :river,
        current_bet: 200,
        active_player_index: 0
      }

      side_pots = BettingRound.side_pots(betting_round)

      # Should create 3 pots:
      # Main pot: 75 * 3 = 225 (all eligible)
      # Side pot 1: (125-75) * 2 = 100 (players 2,3)
      # Side pot 2: (200-125) * 1 = 75 (player 3 only)
      assert length(side_pots) == 3

      [main_pot, side_pot_1, side_pot_2] = side_pots

      assert main_pot.amount == 225
      assert main_pot.eligible_players == MapSet.new([1, 2, 3])

      assert side_pot_1.amount == 100
      assert side_pot_1.eligible_players == MapSet.new([2, 3])

      assert side_pot_2.amount == 75
      assert side_pot_2.eligible_players == MapSet.new([3])
    end
  end
end
