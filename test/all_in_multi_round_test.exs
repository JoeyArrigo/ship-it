defmodule PokerServer.AllInMultiRoundTest do
  use ExUnit.Case
  alias PokerServer.{GameServer, GameManager}

  describe "all-in player state preservation across betting rounds" do
    test "all-in player cannot act in subsequent betting rounds" do
      # Use the same pattern as fold_behavior_test.exs
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

      # Others call to complete preflop and reach flop
      second_state = GameServer.get_state(game_pid)
      second_active = PokerServer.BettingRound.get_active_player(second_state.betting_round)

      {:ok, :action_processed, _} =
        GameServer.player_action(game_pid, second_active.id, {:call})

      third_state = GameServer.get_state(game_pid)
      third_active = PokerServer.BettingRound.get_active_player(third_state.betting_round)

      {:ok, :betting_complete, flop_state} =
        GameServer.player_action(game_pid, third_active.id, {:call})

      # CRITICAL TEST: Verify all-in player is preserved after phase transition
      assert first_active.id in flop_state.betting_round.all_in_players

      # Verify all-in player cannot act
      flop_active = PokerServer.BettingRound.get_active_player(flop_state.betting_round)
      refute flop_active.id == first_active.id

      # Try to make all-in player act - should fail
      result = GameServer.player_action(game_pid, first_active.id, {:check})
      assert {:error, _reason} = result
    end

    test "all-in players preserved through flop and turn transitions" do
      # This test verifies the core fix: all-in state preservation across betting rounds
      # Use 3-player game for simpler betting logic
      players = [{"player1", 1000}, {"player2", 1000}, {"player3", 1000}]
      {:ok, game_id} = GameManager.create_game(players)
      [{game_pid, _}] = Registry.lookup(PokerServer.GameRegistry, game_id)

      {:ok, _} = GameServer.start_hand(game_pid)
      initial_state = GameServer.get_state(game_pid)

      # First active player goes all-in
      first_active = PokerServer.BettingRound.get_active_player(initial_state.betting_round)

      {:ok, :action_processed, _} =
        GameServer.player_action(game_pid, first_active.id, {:all_in})

      # Complete preflop betting
      second_state = GameServer.get_state(game_pid)
      second_active = PokerServer.BettingRound.get_active_player(second_state.betting_round)

      {:ok, :action_processed, _} =
        GameServer.player_action(game_pid, second_active.id, {:call})

      third_state = GameServer.get_state(game_pid)
      third_active = PokerServer.BettingRound.get_active_player(third_state.betting_round)

      {:ok, :betting_complete, flop_state} =
        GameServer.player_action(game_pid, third_active.id, {:call})

      # Verify all-in player preserved after flop transition
      assert first_active.id in flop_state.betting_round.all_in_players

      # Complete flop betting with checks
      flop_active = PokerServer.BettingRound.get_active_player(flop_state.betting_round)

      {:ok, :action_processed, _} =
        GameServer.player_action(game_pid, flop_active.id, {:check})

      next_flop_state = GameServer.get_state(game_pid)
      next_flop_active = PokerServer.BettingRound.get_active_player(next_flop_state.betting_round)

      {:ok, :betting_complete, turn_state} =
        GameServer.player_action(game_pid, next_flop_active.id, {:check})

      # Verify all-in player still preserved after turn transition
      assert first_active.id in turn_state.betting_round.all_in_players
    end
  end
end
