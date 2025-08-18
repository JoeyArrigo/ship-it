defmodule PokerServer.AllInMultiRoundTest do
  use ExUnit.Case
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
        assert flop_active.id != "player1"  # All-in player shouldn't be active
      end
    end
  end
end
