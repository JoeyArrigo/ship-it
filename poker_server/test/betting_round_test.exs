defmodule PokerServer.BettingRoundTest do
  use ExUnit.Case
  alias PokerServer.{BettingRound, Player}

  # Helper to create a player
  defp player(id, chips, position \\ nil), do: %Player{id: id, chips: chips, position: position}

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
      assert betting_round.pot == 30  # SB + BB
      assert betting_round.current_bet == 20
      assert betting_round.active_player_index == 2  # UTG after blinds posted
    end

    test "posts blinds automatically" do
      players = [
        player(1, 1000, 0),  # Small blind
        player(2, 1000, 1),  # Big blind
        player(3, 1000, 2)
      ]
      
      betting_round = BettingRound.new(players, 10, 20, :preflop)
      
      # Check player bets
      player_bets = betting_round.player_bets
      assert player_bets[1] == 10  # Small blind
      assert player_bets[2] == 20  # Big blind
      assert player_bets[3] == 0   # No bet yet
    end

    test "adjusts player chips after posting blinds" do
      players = [
        player(1, 1000, 0),
        player(2, 1000, 1),
        player(3, 1000, 2)
      ]
      
      betting_round = BettingRound.new(players, 10, 20, :preflop)
      
      updated_players = betting_round.players
      assert Enum.find(updated_players, &(&1.id == 1)).chips == 990  # SB paid
      assert Enum.find(updated_players, &(&1.id == 2)).chips == 980  # BB paid
      assert Enum.find(updated_players, &(&1.id == 3)).chips == 1000 # No change
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
      betting_round = BettingRound.new(players, 10, 20, :flop)
      |> Map.put(:current_bet, 0)
      |> Map.put(:player_bets, %{1 => 0, 2 => 0})
      
      actions = BettingRound.valid_actions(betting_round)
      assert :fold in actions
      assert :check in actions
      assert :raise in actions
      refute :call in actions
    end

    test "includes all_in when player has insufficient chips for full raise" do
      players = [player(1, 30, 0), player(2, 1000, 1)]  # Player 1 has only 30 chips
      betting_round = BettingRound.new(players, 10, 20, :preflop)
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
      assert updated_round.pot == 50  # 10 + 20 + 20
      
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
      assert updated_round.pot == 70  # 10 + 20 + 40
      
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
      players = [player(1, 1000, 0), player(2, 30, 1)]  # Player 2 has only 30 chips
      betting_round = BettingRound.new(players, 10, 20, :preflop)
      |> Map.put(:current_bet, 100)
      
      {:ok, updated_round} = BettingRound.process_action(betting_round, 2, {:all_in})
      
      # Player 2 should be all-in
      assert 2 in updated_round.all_in_players
      assert updated_round.player_bets[2] == 30  # All remaining chips
      
      player_2 = Enum.find(updated_round.players, &(&1.id == 2))
      assert player_2.chips == 0
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
      betting_round = BettingRound.new(players, 10, 20, :preflop)
      |> Map.put(:player_bets, %{1 => 20, 2 => 20, 3 => 20})  # All called
      |> Map.put(:pot, 60)
      
      assert BettingRound.betting_complete?(betting_round)
    end

    test "returns true when only one player remains (others folded)" do
      players = [player(1, 1000, 0), player(2, 1000, 1), player(3, 1000, 2)]
      betting_round = BettingRound.new(players, 10, 20, :preflop)
      |> Map.put(:folded_players, MapSet.new([1, 3]))  # Two players folded
      
      assert BettingRound.betting_complete?(betting_round)
    end
  end

  describe "minimum_raise/1" do
    test "returns minimum raise amount" do
      players = [player(1, 1000, 0), player(2, 1000, 1)]
      betting_round = BettingRound.new(players, 10, 20, :preflop)
      
      min_raise = BettingRound.minimum_raise(betting_round)
      assert min_raise == 40  # Big blind * 2
    end

    test "considers previous raise size" do
      players = [player(1, 1000, 0), player(2, 1000, 1)]
      betting_round = BettingRound.new(players, 10, 20, :preflop)
      |> Map.put(:current_bet, 60)  # Someone raised to 60 (40 raise over BB)
      |> Map.put(:last_raise_size, 40)
      
      min_raise = BettingRound.minimum_raise(betting_round)
      assert min_raise == 100  # 60 + 40 (last raise size)
    end
  end

  describe "side_pots/1" do
    test "creates side pots for all-in players" do
      players = [
        player(1, 0, 0),    # All-in with 100 chips
        player(2, 500, 1),  # Active with more chips
        player(3, 1000, 2)  # Active with most chips
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
      assert main_pot.amount == 300  # 100 * 3
      assert main_pot.eligible_players == MapSet.new([1, 2, 3])
      
      assert side_pot.amount == 200  # (200-100) * 2
      assert side_pot.eligible_players == MapSet.new([2, 3])
    end
  end
end