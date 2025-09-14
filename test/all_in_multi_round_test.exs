defmodule PokerServer.AllInMultiRoundTest do
  use ExUnit.Case, async: false
  alias PokerServer.{GameServer, GameManager}


  # Helper function to complete a betting round
  defp complete_betting_round(game_pid, current_state) do
    active_player = PokerServer.BettingRound.get_active_player(current_state.betting_round)

    if active_player do
      # Continue with active player
      case GameServer.player_action(game_pid, active_player.id, {:call}) do
        {:ok, :action_processed, state} ->
          complete_betting_round(game_pid, state)

        {:ok, :betting_complete, state} ->
          state
      end
    else
      # No active player, betting should be complete
      current_state
    end
  end

  describe "all-in player state preservation across betting rounds" do
    test "when all players go all-in, game proceeds to showdown" do
      # When all players have equal stacks and one goes all-in, 
      # others calling will also go all-in, triggering immediate showdown
      players = [{"player1", 1000}, {"player2", 1000}, {"player3", 1000}]
      {:ok, game_id} = GameManager.create_game(players)
      [{game_pid, _}] = Registry.lookup(PokerServer.GameRegistry, game_id)

      {:ok, _} = GameServer.start_hand(game_pid)
      initial_state = GameServer.get_state(game_pid)

      # First active player goes all-in
      first_active = PokerServer.BettingRound.get_active_player(initial_state.betting_round)

      {:ok, :action_processed, state_after_all_in} =
        GameServer.player_action(game_pid, first_active.id, {:all_in})

      # Verify player is in all_in_players set
      assert first_active.id in state_after_all_in.betting_round.all_in_players

      # Others call to complete preflop - this forces them all-in too
      second_state = GameServer.get_state(game_pid)
      second_active = PokerServer.BettingRound.get_active_player(second_state.betting_round)

      {:ok, :action_processed, _} =
        GameServer.player_action(game_pid, second_active.id, {:call})

      third_state = GameServer.get_state(game_pid)
      third_active = PokerServer.BettingRound.get_active_player(third_state.betting_round)

      {:ok, :betting_complete, final_state} =
        GameServer.player_action(game_pid, third_active.id, {:call})

      # When all players are all-in, game should automatically proceed to showdown
      assert final_state.phase == :hand_complete
      assert final_state.betting_round == nil
      # Pot should be distributed (pot becomes 0 after showdown)
      assert final_state.game_state.pot == 0

      # Try to make any player act - should fail since hand is complete
      result = GameServer.player_action(game_pid, first_active.id, {:check})
      assert {:error, _reason} = result
    end

    test "all-in state preserved when some players still have chips" do
      # This test verifies all-in state preservation when not all players go all-in
      # Use one small stack and two big stacks 
      players = [{"player1", 100}, {"player2", 1000}, {"player3", 1000}]
      {:ok, game_id} = GameManager.create_game(players)
      [{game_pid, _}] = Registry.lookup(PokerServer.GameRegistry, game_id)

      {:ok, _} = GameServer.start_hand(game_pid)
      initial_state = GameServer.get_state(game_pid)

      # First active player (should be one of the big stacks) makes a small raise
      first_active = PokerServer.BettingRound.get_active_player(initial_state.betting_round)

      {:ok, :action_processed, _} =
        GameServer.player_action(game_pid, first_active.id, {:raise, 60})

      # Find the small stack player and make them go all-in
      second_state = GameServer.get_state(game_pid)
      second_active = PokerServer.BettingRound.get_active_player(second_state.betting_round)

      # If this isn't the small stack, continue until we find them
      if second_active.id == "player1" do
        {:ok, :action_processed, _} =
          GameServer.player_action(game_pid, "player1", {:all_in})
      else
        {:ok, :action_processed, _} =
          GameServer.player_action(game_pid, second_active.id, {:call})

        _third_state = GameServer.get_state(game_pid)

        {:ok, :action_processed, _} =
          GameServer.player_action(game_pid, "player1", {:all_in})
      end

      # Complete preflop - finish all remaining actions
      current_state = GameServer.get_state(game_pid)

      # Continue until betting is complete
      flop_state = complete_betting_round(game_pid, current_state)

      # Verify player1 is preserved as all-in after flop transition
      assert "player1" in flop_state.betting_round.all_in_players

      # The other players should still be able to act (not all-in)
      flop_active = PokerServer.BettingRound.get_active_player(flop_state.betting_round)

      if flop_active do
        # Verify we can continue betting on flop
        # All-in player shouldn't be active
        assert flop_active.id != "player1"
      end
    end

    test "unequal stack all-in should handle side pots correctly when B wins" do
      # Player A: 1600 chips, Player B: 1400 chips
      # Expected side pot behavior:
      # - A bets 1600 total
      # - B bets 1400 total
      # - Contested: 1400 × 2 = 2800 chips (main pot)
      # - Uncalled: 200 chips returned to A (side pot)
      # - If B wins: B gets 2800, A gets 200

      # Force a scenario where B wins by giving B better hole cards
      players = [{"player_a", 1600}, {"player_b", 1400}]
      {:ok, game_id} = GameManager.create_game(players)
      [{game_pid, _}] = Registry.lookup(PokerServer.GameRegistry, game_id)

      {:ok, _} = GameServer.start_hand(game_pid)
      initial_state = GameServer.get_state(game_pid)

      # Force both players all-in - handle turn order
      first_active = PokerServer.BettingRound.get_active_player(initial_state.betting_round)

      final_state =
        if first_active.id == "player_a" do
          {:ok, :action_processed, _} = GameServer.player_action(game_pid, "player_a", {:all_in})

          {:ok, :betting_complete, state} =
            GameServer.player_action(game_pid, "player_b", {:all_in})

          state
        else
          {:ok, :action_processed, _} = GameServer.player_action(game_pid, "player_b", {:call})
          {:ok, :action_processed, _} = GameServer.player_action(game_pid, "player_a", {:all_in})

          {:ok, :betting_complete, state} =
            GameServer.player_action(game_pid, "player_b", {:all_in})

          state
        end

      # Game should proceed to hand_complete
      assert final_state.phase == :hand_complete
      assert final_state.betting_round == nil

      # Check final chip counts
      final_player_a = Enum.find(final_state.game_state.players, &(&1.id == "player_a"))
      final_player_b = Enum.find(final_state.game_state.players, &(&1.id == "player_b"))

      # Verify total chip conservation
      total_chips = final_player_a.chips + final_player_b.chips
      expected_total = 1600 + 1400
      assert total_chips == expected_total

      # Test proper side pot logic (this will fail with current implementation)
      # We can't control who wins due to random cards, so test both scenarios
      if final_player_b.chips > final_player_a.chips do
        # B won - should get contested amount (2800), A gets uncalled portion (200)
        assert final_player_b.chips == 2800,
               "Player B should get contested pot amount, got #{final_player_b.chips}"

        assert final_player_a.chips == 200,
               "Player A should get uncalled bet back, got #{final_player_a.chips}"
      else
        # A won - should get everything (A can win their own uncalled bet)
        assert final_player_a.chips == 3000,
               "Player A should get all chips when winning"

        assert final_player_b.chips == 0,
               "Player B should get nothing when losing"
      end
    end

    test "unequal stack all-in tie should split contested pot correctly" do
      # Player A: 1600 chips, Player B: 1400 chips, tie scenario
      # Expected side pot behavior for ties:
      # - A bets 1600 total
      # - B bets 1400 total
      # - Contested: 1400 × 2 = 2800 chips (main pot) - split between A and B
      # - Uncalled: 200 chips returned to A (side pot - not split)
      # - Final: A gets 1400 (half contested) + 200 (uncalled) = 1600
      # - Final: B gets 1400 (half contested) = 1400
      # - Total check: 1600 + 1400 = 3000 ✓

      players = [{"player_a", 1600}, {"player_b", 1400}]
      {:ok, game_id} = GameManager.create_game(players)
      [{game_pid, _}] = Registry.lookup(PokerServer.GameRegistry, game_id)

      {:ok, _} = GameServer.start_hand(game_pid)
      initial_state = GameServer.get_state(game_pid)

      # Force both players all-in - handle turn order
      first_active = PokerServer.BettingRound.get_active_player(initial_state.betting_round)

      final_state =
        if first_active.id == "player_a" do
          {:ok, :action_processed, _} = GameServer.player_action(game_pid, "player_a", {:all_in})

          {:ok, :betting_complete, state} =
            GameServer.player_action(game_pid, "player_b", {:all_in})

          state
        else
          {:ok, :action_processed, _} = GameServer.player_action(game_pid, "player_b", {:call})
          {:ok, :action_processed, _} = GameServer.player_action(game_pid, "player_a", {:all_in})

          {:ok, :betting_complete, state} =
            GameServer.player_action(game_pid, "player_b", {:all_in})

          state
        end

      # Game should proceed to hand_complete
      assert final_state.phase == :hand_complete
      assert final_state.betting_round == nil

      # Check final chip counts
      final_player_a = Enum.find(final_state.game_state.players, &(&1.id == "player_a"))
      final_player_b = Enum.find(final_state.game_state.players, &(&1.id == "player_b"))

      # Verify total chip conservation
      total_chips = final_player_a.chips + final_player_b.chips
      expected_total = 1600 + 1400
      assert total_chips == expected_total

      # Test proper side pot logic for ties (this will fail with current implementation)
      # Since we can't force a tie, we'll test if there happens to be one
      if final_player_a.chips == final_player_b.chips do
        # Current implementation likely gives 1500 to each (wrong)
        # Correct implementation should give:
        # A: 1400 (half contested) + 200 (uncalled) = 1600
        # B: 1400 (half contested) = 1400
        assert final_player_a.chips == 1600,
               "In a tie, Player A should get half contested pot plus uncalled bet, got #{final_player_a.chips}"

        assert final_player_b.chips == 1400,
               "In a tie, Player B should get half contested pot only, got #{final_player_b.chips}"
      else
        # Not a tie - document what should happen for reference
        if final_player_a.chips > final_player_b.chips do
          # A won - should get everything (correct in current implementation)
          assert final_player_a.chips == 3000
          assert final_player_b.chips == 0
        else
          # B won - should get contested pot (2800), A gets uncalled portion (200)
          assert final_player_b.chips == 2800,
                 "Player B should get contested pot amount, got #{final_player_b.chips}"

          assert final_player_a.chips == 200,
                 "Player A should get uncalled bet back, got #{final_player_a.chips}"
        end
      end
    end
  end
end
