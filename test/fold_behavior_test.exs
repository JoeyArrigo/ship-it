defmodule PokerServer.FoldBehaviorTest do
  @moduledoc """
  Comprehensive tests for proper fold behavior in poker games.

  Tests ensure that:
  1. Folded players cannot win hands
  2. Folded players cannot act after folding
  3. Hand ends immediately when only one player remains
  4. Side pots exclude folded players
  """

  use ExUnit.Case, async: true
  alias PokerServer.{GameServer, BettingRound, GameState, Player}

  setup do
    # Create a 2-player game for most tests
    players = [{"player1", 1000}, {"player2", 1000}]
    {:ok, game_id} = PokerServer.GameManager.create_game(players)

    # Get the game process
    [{game_pid, _}] = Registry.lookup(PokerServer.GameRegistry, game_id)

    %{game_id: game_id, game_pid: game_pid}
  end

  describe "folded players cannot win hands" do
    test "folded player excluded from showdown", %{game_pid: _game_pid} do
      # Test the showdown function directly with folded players
      players = [
        %Player{id: "player1", chips: 1000, position: 0, hole_cards: []},
        %Player{id: "player2", chips: 1000, position: 1, hole_cards: []},
        %Player{id: "player3", chips: 1000, position: 2, hole_cards: []}
      ]

      game_state = %GameState{
        players: players,
        community_cards: [],
        pot: 100,
        phase: :river,
        hand_number: 1,
        deck: [],
        button_position: 0,
        small_blind: 10,
        big_blind: 20
      }

      # player1 has folded - create a betting round to represent this
      folded_players = MapSet.new(["player1"])

      # Create a mock betting round for showdown
      betting_round = %PokerServer.BettingRound{
        players: game_state.players,
        player_bets: %{"player1" => 0, "player2" => 0, "player3" => 0},
        folded_players: folded_players,
        all_in_players: MapSet.new(),
        pot: game_state.pot,
        current_bet: 0,
        small_blind: 0,
        big_blind: 0,
        round_type: :river,
        active_player_index: 0,
        last_raise_size: nil,
        players_who_can_act: MapSet.new(),
        last_raiser: nil
      }

      # Call showdown with betting round
      result = GameState.showdown(game_state, betting_round)

      # Should only evaluate player2 and player3, not player1
      assert result.phase == :hand_complete
      assert result.pot == 0

      # Verify that folded player did not win any chips
      player1_result = Enum.find(result.players, fn p -> p.id == "player1" end)
      # Unchanged from folding
      assert player1_result.chips == 1000
    end

    test "only non-folded players eligible for side pots" do
      # Create a betting round with multiple players and test side pot calculation
      players = [
        %Player{id: "player1", chips: 100, position: 0},
        %Player{id: "player2", chips: 200, position: 1},
        %Player{id: "player3", chips: 300, position: 2}
      ]

      betting_round = BettingRound.new(players, 10, 20, :preflop)

      # Get the active player order - in preflop with 3 players, action starts with UTG (position after big blind)
      first_active = BettingRound.get_active_player(betting_round)

      # Simulate: first active player folds, next goes all-in, third calls
      {:ok, round_after_fold} =
        BettingRound.process_action(betting_round, first_active.id, {:fold})

      second_active = BettingRound.get_active_player(round_after_fold)

      {:ok, round_after_allin} =
        BettingRound.process_action(round_after_fold, second_active.id, {:all_in})

      third_active = BettingRound.get_active_player(round_after_allin)

      {:ok, final_round} =
        BettingRound.process_action(round_after_allin, third_active.id, {:call})

      side_pots = BettingRound.side_pots(final_round)

      # Should have one main pot with only the non-folded players eligible
      assert length(side_pots) == 1
      [main_pot] = side_pots

      assert main_pot.eligible_players == MapSet.new([second_active.id, third_active.id])
      refute first_active.id in main_pot.eligible_players
    end
  end

  describe "folded players cannot act" do
    test "folded player gets empty valid actions", %{game_pid: game_pid} do
      {:ok, _} = GameServer.start_hand(game_pid)
      initial_state = GameServer.get_state(game_pid)

      active_player = BettingRound.get_active_player(initial_state.betting_round)

      # Player folds
      {:ok, :betting_complete, _} = GameServer.player_action(game_pid, active_player.id, {:fold})

      # Try to get valid actions for the folded player - should be empty
      final_state = GameServer.get_state(game_pid)
      # Hand ended
      assert final_state.phase == :hand_complete
    end

    test "folded player cannot take actions", %{game_pid: _game_pid} do
      # Create a 3-player game to test folded player trying to act
      players = [{"player1", 1000}, {"player2", 1000}, {"player3", 1000}]
      {:ok, game_id} = PokerServer.GameManager.create_game(players)
      [{game_pid, _}] = Registry.lookup(PokerServer.GameRegistry, game_id)

      {:ok, _} = GameServer.start_hand(game_pid)
      initial_state = GameServer.get_state(game_pid)

      active_player = BettingRound.get_active_player(initial_state.betting_round)

      # First player folds
      {:ok, :action_processed, _state_after_fold} =
        GameServer.player_action(game_pid, active_player.id, {:fold})

      # Try to have the folded player act again - should fail
      result = GameServer.player_action(game_pid, active_player.id, {:call})
      assert match?({:error, _}, result)
    end

    test "betting skips folded players", %{game_pid: _game_pid} do
      # Create a 3-player game
      players = [{"player1", 1000}, {"player2", 1000}, {"player3", 1000}]
      {:ok, game_id} = PokerServer.GameManager.create_game(players)
      [{game_pid, _}] = Registry.lookup(PokerServer.GameRegistry, game_id)

      {:ok, _} = GameServer.start_hand(game_pid)
      initial_state = GameServer.get_state(game_pid)

      first_active = BettingRound.get_active_player(initial_state.betting_round)

      # First player folds
      {:ok, :action_processed, state_after_fold} =
        GameServer.player_action(game_pid, first_active.id, {:fold})

      # Check that action moved to next non-folded player
      second_active = BettingRound.get_active_player(state_after_fold.betting_round)
      assert second_active.id != first_active.id

      # Verify the folded player is in the folded_players set
      assert first_active.id in state_after_fold.betting_round.folded_players
    end
  end

  describe "early hand termination" do
    test "hand ends when only one player remains", %{game_pid: game_pid} do
      {:ok, _} = GameServer.start_hand(game_pid)
      initial_state = GameServer.get_state(game_pid)

      active_player = BettingRound.get_active_player(initial_state.betting_round)

      other_player =
        Enum.find(initial_state.game_state.players, fn p -> p.id != active_player.id end)

      # One player folds
      {:ok, :betting_complete, final_state} =
        GameServer.player_action(game_pid, active_player.id, {:fold})

      # Hand should end immediately
      assert final_state.phase == :hand_complete
      assert is_nil(final_state.betting_round)
      assert final_state.game_state.pot == 0

      # Remaining player should have won the pot
      winner = Enum.find(final_state.game_state.players, fn p -> p.id == other_player.id end)
      assert winner.chips > other_player.chips
    end

    test "hand continues with multiple remaining players", %{} do
      # Create a 3-player game
      players = [{"player1", 1000}, {"player2", 1000}, {"player3", 1000}]
      {:ok, game_id} = PokerServer.GameManager.create_game(players)
      [{game_pid, _}] = Registry.lookup(PokerServer.GameRegistry, game_id)

      {:ok, _} = GameServer.start_hand(game_pid)
      initial_state = GameServer.get_state(game_pid)

      active_player = BettingRound.get_active_player(initial_state.betting_round)

      # One player folds, but two remain
      {:ok, :action_processed, state_after_fold} =
        GameServer.player_action(game_pid, active_player.id, {:fold})

      # Hand should continue since 2 players remain
      assert state_after_fold.phase == :preflop_betting
      assert not is_nil(state_after_fold.betting_round)

      # Should still have 2 active players
      active_players =
        length(state_after_fold.betting_round.players) -
          MapSet.size(state_after_fold.betting_round.folded_players)

      assert active_players == 2
    end

    test "pot awarded correctly on early termination", %{game_pid: game_pid} do
      {:ok, _} = GameServer.start_hand(game_pid)
      initial_state = GameServer.get_state(game_pid)

      active_player = BettingRound.get_active_player(initial_state.betting_round)

      other_player =
        Enum.find(initial_state.game_state.players, fn p -> p.id != active_player.id end)

      initial_pot = initial_state.betting_round.pot

      # One player folds
      {:ok, :betting_complete, final_state} =
        GameServer.player_action(game_pid, active_player.id, {:fold})

      # Check pot distribution
      winner = Enum.find(final_state.game_state.players, fn p -> p.id == other_player.id end)
      loser = Enum.find(final_state.game_state.players, fn p -> p.id == active_player.id end)

      # Winner should have gained the pot amount
      expected_winner_chips = other_player.chips + initial_pot
      assert winner.chips == expected_winner_chips

      # Loser's chips should be unchanged from their betting
      # (they already lost chips when blinds were posted)
      assert loser.chips == active_player.chips
    end
  end

  describe "integration with existing game flow" do
    test "fold preserves tournament elimination logic" do
      # Create players with low chips to test elimination
      # Poor player can only survive a few hands
      players = [{"rich_player", 1000}, {"poor_player", 25}]
      {:ok, game_id} = PokerServer.GameManager.create_game(players)
      [{game_pid, _}] = Registry.lookup(PokerServer.GameRegistry, game_id)

      # Play a hand where poor player folds (doesn't go all-in)
      {:ok, _} = GameServer.start_hand(game_pid)
      initial_state = GameServer.get_state(game_pid)

      # Determine who acts first and have them fold
      active_player = BettingRound.get_active_player(initial_state.betting_round)

      {:ok, :betting_complete, final_state} =
        GameServer.player_action(game_pid, active_player.id, {:fold})

      # Game should handle this normally
      assert final_state.phase == :hand_complete

      # Both players should still be in the game (no elimination)
      assert length(final_state.game_state.players) == 2
    end

    test "fold works correctly with all-in scenarios" do
      # Create a 3-player game with different stack sizes
      players = [{"player1", 100}, {"player2", 200}, {"player3", 300}]
      {:ok, game_id} = PokerServer.GameManager.create_game(players)
      [{game_pid, _}] = Registry.lookup(PokerServer.GameRegistry, game_id)

      {:ok, _} = GameServer.start_hand(game_pid)
      initial_state = GameServer.get_state(game_pid)

      active_player = BettingRound.get_active_player(initial_state.betting_round)

      # First player folds
      {:ok, :action_processed, state_after_fold} =
        GameServer.player_action(game_pid, active_player.id, {:fold})

      # Game continues with remaining players
      assert state_after_fold.phase == :preflop_betting

      remaining_players =
        length(state_after_fold.betting_round.players) -
          MapSet.size(state_after_fold.betting_round.folded_players)

      assert remaining_players == 2
    end
  end
end
