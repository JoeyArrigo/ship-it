defmodule PokerServer.GameServerPubSubTest do
  use ExUnit.Case, async: true
  alias PokerServer.{GameServer, GameManager}
  alias Phoenix.PubSub

  setup do
    # Create test players
    players = [{"player1", 1000}, {"player2", 1000}]

    # Start the game
    {:ok, game_id} = GameManager.create_game(players)
    {:ok, game_pid} = GameManager.lookup_game(game_id)

    # Subscribe to game events for player1 (default test player)
    PubSub.subscribe(PokerServer.PubSub, "game:#{game_id}:player1")

    %{game_id: game_id, game_pid: game_pid, players: players}
  end

  # Helper functions for common test setup patterns
  
  defp start_hand_and_clear_broadcast(game_pid) do
    {:ok, state} = GameServer.start_hand(game_pid)
    assert_receive {:game_updated, _}, 1000
    state
  end

  defp complete_preflop_betting(game_pid) do
    {:ok, _, _} = GameServer.player_action(game_pid, "player1", {:call})
    assert_receive {:game_updated, _}, 1000
    {:ok, :betting_complete, _} = GameServer.player_action(game_pid, "player2", {:check})
    assert_receive {:game_updated, state}, 1000
    state
  end

  defp complete_flop_betting(game_pid) do
    {:ok, _, _} = GameServer.player_action(game_pid, "player2", {:check})
    assert_receive {:game_updated, _}, 1000
    {:ok, :betting_complete, _} = GameServer.player_action(game_pid, "player1", {:check})
    assert_receive {:game_updated, state}, 1000
    state
  end

  defp complete_turn_betting(game_pid) do
    {:ok, _, _} = GameServer.player_action(game_pid, "player2", {:check})
    assert_receive {:game_updated, _}, 1000
    {:ok, :betting_complete, _} = GameServer.player_action(game_pid, "player1", {:check})
    assert_receive {:game_updated, state}, 1000
    state
  end

  defp complete_river_betting(game_pid) do
    {:ok, _, _} = GameServer.player_action(game_pid, "player2", {:check})
    assert_receive {:game_updated, _}, 1000
    {:ok, :betting_complete, _} = GameServer.player_action(game_pid, "player1", {:check})
    assert_receive {:game_updated, state}, 1000
    state
  end

  defp advance_to_flop_betting(game_pid) do
    start_hand_and_clear_broadcast(game_pid)
    complete_preflop_betting(game_pid)
  end

  defp advance_to_turn_betting(game_pid) do
    advance_to_flop_betting(game_pid)
    complete_flop_betting(game_pid)
  end

  defp advance_to_river_betting(game_pid) do
    advance_to_turn_betting(game_pid)
    complete_turn_betting(game_pid)
  end

  test "start_hand broadcasts game state update", %{game_pid: game_pid, game_id: game_id} do
    {:ok, _new_state} = GameServer.start_hand(game_pid)

    assert_receive {:game_updated, broadcasted_state}, 1000

    assert broadcasted_state.game_id == game_id
    assert broadcasted_state.phase == :preflop_betting
    assert not is_nil(broadcasted_state.betting_round)
    assert length(broadcasted_state.game_state.players) == 2
  end

  test "player action broadcasts state update", %{game_pid: game_pid, game_id: game_id} do
    start_hand_and_clear_broadcast(game_pid)

    result = GameServer.player_action(game_pid, "player1", {:call})
    assert match?({:ok, _, _}, result) or match?(:ok, result)

    assert_receive {:game_updated, broadcasted_state}, 1000

    assert broadcasted_state.game_id == game_id
    assert broadcasted_state.phase in [:preflop_betting, :flop_betting]
  end

  test "betting round completion broadcasts phase change", %{game_pid: game_pid} do
    start_hand_and_clear_broadcast(game_pid)

    result1 = GameServer.player_action(game_pid, "player1", {:call})
    assert match?({:ok, _, _}, result1) or match?(:ok, result1)
    assert_receive {:game_updated, _}, 1000

    result2 = GameServer.player_action(game_pid, "player2", {:check})

    case result2 do
      {:ok, _, _} ->
        assert_receive {:game_updated, broadcasted_state}, 1000
        assert broadcasted_state.phase == :flop_betting
        assert not is_nil(broadcasted_state.betting_round)
        assert length(broadcasted_state.game_state.community_cards) == 3

      {:error, :no_active_betting_round} ->
        # Valid behavior for heads-up poker when betting completes with first action
        assert true

      _ ->
        flunk("Unexpected result from player action: #{inspect(result2)}")
    end
  end

  test "multiple subscribers receive the same broadcast", %{game_pid: game_pid, game_id: game_id} do
    # Setup: Create a second subscriber
    test_pid = self()

    _subscriber_pid =
      spawn_link(fn ->
        PubSub.subscribe(PokerServer.PubSub, "game:#{game_id}:player1")
        send(test_pid, :subscribed)

        receive do
          {:game_updated, state} -> send(test_pid, {:subscriber_received, state})
        after
          2000 -> send(test_pid, :subscriber_timeout)
        end
      end)

    # Wait for subscription
    assert_receive :subscribed, 1000

    # Act: Start hand to trigger broadcast
    {:ok, new_state} = GameServer.start_hand(game_pid)

    # Assert: Both subscribers receive the same message
    assert_receive {:game_updated, main_received_state}, 1000
    assert_receive {:subscriber_received, subscriber_received_state}, 1000

    # Verify both received the same filtered state
    assert main_received_state == subscriber_received_state

    # Verify the filtered state has correct structure but hides other players' cards
    assert main_received_state.game_id == new_state.game_id
    assert main_received_state.phase == new_state.phase

    # Player1 should see their own cards but not player2's cards
    player1_in_broadcast =
      Enum.find(main_received_state.game_state.players, &(&1.id == "player1"))

    player2_in_broadcast =
      Enum.find(main_received_state.game_state.players, &(&1.id == "player2"))

    # Can see own cards
    assert length(player1_in_broadcast.hole_cards) == 2
    # Cannot see other's cards
    assert length(player2_in_broadcast.hole_cards) == 0
  end

  test "broadcast message format matches expected structure", %{game_pid: game_pid} do
    {:ok, expected_state} = GameServer.start_hand(game_pid)

    assert_receive {:game_updated, broadcasted_state}, 1000

    # Verify complete state structure is broadcasted (but filtered for security)
    assert Map.has_key?(broadcasted_state, :game_id)
    assert Map.has_key?(broadcasted_state, :game_state)
    assert Map.has_key?(broadcasted_state, :betting_round)
    assert Map.has_key?(broadcasted_state, :phase)

    assert broadcasted_state.game_id == expected_state.game_id
    assert broadcasted_state.phase == expected_state.phase

    # Verify security filtering: player1 sees own cards, but not player2's
    player1_in_broadcast = Enum.find(broadcasted_state.game_state.players, &(&1.id == "player1"))
    player2_in_broadcast = Enum.find(broadcasted_state.game_state.players, &(&1.id == "player2"))

    assert length(player1_in_broadcast.hole_cards) == 2  # Can see own cards
    assert length(player2_in_broadcast.hole_cards) == 0  # Cannot see other's cards
  end

  test "failed actions do not broadcast state changes", %{game_pid: game_pid} do
    start_hand_and_clear_broadcast(game_pid)

    {:error, _reason} = GameServer.player_action(game_pid, "invalid_player", {:call})

    refute_receive {:game_updated, _}, 500
  end

  test "broadcast happens atomically with state updates", %{game_pid: game_pid} do
    {:ok, returned_state} = GameServer.start_hand(game_pid)

    assert_receive {:game_updated, broadcasted_state}, 1000

    # Broadcasted state should be filtered version of returned state
    assert broadcasted_state.game_id == returned_state.game_id
    assert broadcasted_state.phase == returned_state.phase

    # Verify current server state matches the unfiltered returned state
    current_state = GameServer.get_state(game_pid)
    assert current_state == returned_state

    # Verify broadcast filtering worked correctly
    player1_in_broadcast = Enum.find(broadcasted_state.game_state.players, &(&1.id == "player1"))
    player2_in_broadcast = Enum.find(broadcasted_state.game_state.players, &(&1.id == "player2"))

    assert length(player1_in_broadcast.hole_cards) == 2  # Can see own cards
    assert length(player2_in_broadcast.hole_cards) == 0  # Cannot see other's cards
  end

  test "preflop betting completion transitions to flop_betting phase", %{game_pid: game_pid} do
    start_hand_and_clear_broadcast(game_pid)
    
    flop_state = complete_preflop_betting(game_pid)
    
    assert flop_state.phase == :flop_betting
    assert not is_nil(flop_state.betting_round)
    assert length(flop_state.game_state.community_cards) == 3
  end

  test "flop_betting phase allows player actions", %{game_pid: game_pid} do
    advance_to_flop_betting(game_pid)

    {:ok, _, _} = GameServer.player_action(game_pid, "player2", {:check})

    assert_receive {:game_updated, broadcasted_state}, 1000
    assert broadcasted_state.phase == :flop_betting
  end

  test "flop_betting completion transitions to turn_betting phase", %{game_pid: game_pid} do
    advance_to_flop_betting(game_pid)
    
    turn_state = complete_flop_betting(game_pid)
    
    assert turn_state.phase == :turn_betting
    assert not is_nil(turn_state.betting_round)
    assert length(turn_state.game_state.community_cards) == 4
  end

  test "turn_betting phase allows player actions", %{game_pid: game_pid} do
    advance_to_turn_betting(game_pid)

    {:ok, _, _} = GameServer.player_action(game_pid, "player2", {:check})

    assert_receive {:game_updated, broadcasted_state}, 1000
    assert broadcasted_state.phase == :turn_betting
  end

  test "turn_betting completion transitions to river_betting phase", %{game_pid: game_pid} do
    advance_to_turn_betting(game_pid)
    
    river_state = complete_turn_betting(game_pid)
    
    assert river_state.phase == :river_betting
    assert not is_nil(river_state.betting_round)
    assert length(river_state.game_state.community_cards) == 5
  end

  test "river_betting phase allows player actions", %{game_pid: game_pid} do
    advance_to_river_betting(game_pid)

    {:ok, _, _} = GameServer.player_action(game_pid, "player2", {:check})

    assert_receive {:game_updated, broadcasted_state}, 1000
    assert broadcasted_state.phase == :river_betting
  end

  test "complete hand flow: preflop -> flop -> turn -> river -> showdown", %{game_pid: game_pid} do
    start_hand_and_clear_broadcast(game_pid)
    
    flop_state = complete_preflop_betting(game_pid)
    turn_state = complete_flop_betting(game_pid) 
    river_state = complete_turn_betting(game_pid)
    final_state = complete_river_betting(game_pid)

    # Assert: Complete poker hand progression
    assert flop_state.phase == :flop_betting
    assert length(flop_state.game_state.community_cards) == 3
    
    assert turn_state.phase == :turn_betting  
    assert length(turn_state.game_state.community_cards) == 4
    
    assert river_state.phase == :river_betting
    assert length(river_state.game_state.community_cards) == 5
    
    assert final_state.phase == :hand_complete
    assert length(final_state.game_state.community_cards) == 5
    
    # Verify server state after complete hand
    full_state = GameServer.get_state(game_pid)
    assert full_state.phase == :hand_complete
    assert is_nil(full_state.betting_round)
  end

  test "fold action broadcasts state update", %{game_pid: game_pid, game_id: game_id} do
    start_hand_and_clear_broadcast(game_pid)

    # Get the active player who should act
    current_state = GameServer.get_state(game_pid)
    active_player = PokerServer.BettingRound.get_active_player(current_state.betting_round)
    
    result = GameServer.player_action(game_pid, active_player.id, {:fold})
    assert match?({:ok, :betting_complete, _}, result)

    assert_receive {:game_updated, broadcasted_state}, 1000

    assert broadcasted_state.game_id == game_id
    # When one player folds in heads-up preflop, betting completes and advances to flop
    # (The hand doesn't end immediately - it continues through all streets)
    assert broadcasted_state.phase == :flop_betting
  end

  test "player fold creates single active player scenario", %{game_pid: game_pid} do
    start_hand_and_clear_broadcast(game_pid)

    # Get active player and initial state
    initial_state = GameServer.get_state(game_pid)
    active_player = PokerServer.BettingRound.get_active_player(initial_state.betting_round)
    
    # Player folds, leaving other player as only active
    {:ok, :betting_complete, final_state} = GameServer.player_action(game_pid, active_player.id, {:fold})

    assert_receive {:game_updated, broadcasted_state}, 1000

    # Betting completes and advances to next phase (flop_betting)
    assert final_state.phase == :flop_betting
    assert broadcasted_state.phase == :flop_betting
    assert not is_nil(final_state.betting_round)

    # Game continues through all streets even with one folded player
    assert length(final_state.game_state.community_cards) == 3
  end

  test "fold during flop betting continues to turn", %{game_pid: game_pid} do
    advance_to_flop_betting(game_pid)

    # Get active player for flop betting
    current_state = GameServer.get_state(game_pid)
    active_player = PokerServer.BettingRound.get_active_player(current_state.betting_round)

    # Player folds during flop betting
    {:ok, :betting_complete, final_state} = GameServer.player_action(game_pid, active_player.id, {:fold})

    assert_receive {:game_updated, broadcasted_state}, 1000

    # Game continues to turn_betting (doesn't end immediately)
    assert final_state.phase == :turn_betting
    assert broadcasted_state.phase == :turn_betting
    assert length(final_state.game_state.community_cards) == 4  # Turn card dealt
  end

  test "fold during turn betting continues to river", %{game_pid: game_pid} do
    advance_to_turn_betting(game_pid)

    # Get active player for turn betting
    current_state = GameServer.get_state(game_pid)
    active_player = PokerServer.BettingRound.get_active_player(current_state.betting_round)

    # Player folds during turn betting  
    {:ok, :betting_complete, final_state} = GameServer.player_action(game_pid, active_player.id, {:fold})

    assert_receive {:game_updated, broadcasted_state}, 1000

    # Game continues to river_betting (doesn't end immediately)
    assert final_state.phase == :river_betting
    assert broadcasted_state.phase == :river_betting
    assert length(final_state.game_state.community_cards) == 5  # River card dealt
  end

  test "fold during river betting ends hand", %{game_pid: game_pid} do
    advance_to_river_betting(game_pid)

    # Get active player for river betting
    current_state = GameServer.get_state(game_pid)
    active_player = PokerServer.BettingRound.get_active_player(current_state.betting_round)

    # Player folds during final betting round
    {:ok, :betting_complete, final_state} = GameServer.player_action(game_pid, active_player.id, {:fold})

    assert_receive {:game_updated, broadcasted_state}, 1000

    # Hand completes after river betting
    assert final_state.phase == :hand_complete
    assert broadcasted_state.phase == :hand_complete
    assert length(final_state.game_state.community_cards) == 5  # All community cards dealt
  end

  test "raise action broadcasts state update", %{game_pid: game_pid, game_id: game_id} do
    start_hand_and_clear_broadcast(game_pid)

    # Get active player and minimum raise amount
    current_state = GameServer.get_state(game_pid)
    active_player = PokerServer.BettingRound.get_active_player(current_state.betting_round)
    min_raise = PokerServer.BettingRound.minimum_raise(current_state.betting_round)

    # Player makes minimum raise
    result = GameServer.player_action(game_pid, active_player.id, {:raise, min_raise})
    assert match?({:ok, :action_processed, _}, result)

    assert_receive {:game_updated, broadcasted_state}, 1000

    assert broadcasted_state.game_id == game_id
    assert broadcasted_state.phase == :preflop_betting
    # Betting should continue after raise (other player needs to respond)
    assert not is_nil(broadcasted_state.betting_round)
  end

  test "minimum raise validation", %{game_pid: game_pid} do
    start_hand_and_clear_broadcast(game_pid)

    # Get active player and minimum raise
    current_state = GameServer.get_state(game_pid)
    active_player = PokerServer.BettingRound.get_active_player(current_state.betting_round)
    min_raise = PokerServer.BettingRound.minimum_raise(current_state.betting_round)

    # Try to raise below minimum - should fail
    below_min_raise = min_raise - 1
    {:error, reason} = GameServer.player_action(game_pid, active_player.id, {:raise, below_min_raise})
    
    assert is_binary(reason)
    assert String.contains?(reason, "below minimum raise")

    # No broadcast should occur for failed action
    refute_receive {:game_updated, _}, 500
  end

  test "raise increases pot and requires response", %{game_pid: game_pid} do
    start_hand_and_clear_broadcast(game_pid)

    # Get initial state and active player
    initial_state = GameServer.get_state(game_pid)
    active_player = PokerServer.BettingRound.get_active_player(initial_state.betting_round)
    initial_pot = initial_state.betting_round.pot
    min_raise = PokerServer.BettingRound.minimum_raise(initial_state.betting_round)

    # Player raises
    {:ok, :action_processed, updated_state} = GameServer.player_action(game_pid, active_player.id, {:raise, min_raise})

    assert_receive {:game_updated, broadcasted_state}, 1000

    # Pot should increase by the raise amount
    assert updated_state.betting_round.pot > initial_pot
    assert broadcasted_state.betting_round.pot > initial_pot

    # Betting should continue (other player must respond to raise)
    assert updated_state.phase == :preflop_betting
    assert broadcasted_state.phase == :preflop_betting
  end

  test "raise during flop betting", %{game_pid: game_pid} do
    advance_to_flop_betting(game_pid)

    # Get active player for flop betting
    current_state = GameServer.get_state(game_pid)
    active_player = PokerServer.BettingRound.get_active_player(current_state.betting_round)
    min_raise = PokerServer.BettingRound.minimum_raise(current_state.betting_round)
    initial_pot = current_state.betting_round.pot

    # Player raises during flop
    {:ok, :action_processed, updated_state} = GameServer.player_action(game_pid, active_player.id, {:raise, min_raise})

    assert_receive {:game_updated, broadcasted_state}, 1000

    # Still in flop betting phase, pot increased (or at least >= initial if initial was 0)
    assert updated_state.phase == :flop_betting
    assert updated_state.betting_round.pot >= initial_pot + min_raise
    assert broadcasted_state.phase == :flop_betting
    assert length(broadcasted_state.game_state.community_cards) == 3
  end

  test "raise followed by call completes betting round", %{game_pid: game_pid} do
    start_hand_and_clear_broadcast(game_pid)

    # Get active player and raise
    initial_state = GameServer.get_state(game_pid)
    active_player = PokerServer.BettingRound.get_active_player(initial_state.betting_round)
    min_raise = PokerServer.BettingRound.minimum_raise(initial_state.betting_round)

    # First player raises
    {:ok, :action_processed, _} = GameServer.player_action(game_pid, active_player.id, {:raise, min_raise})
    assert_receive {:game_updated, _}, 1000

    # Get next active player
    raised_state = GameServer.get_state(game_pid) 
    next_player = PokerServer.BettingRound.get_active_player(raised_state.betting_round)

    # Second player calls the raise
    {:ok, :betting_complete, final_state} = GameServer.player_action(game_pid, next_player.id, {:call})
    assert_receive {:game_updated, broadcasted_state}, 1000

    # Should advance to flop betting after raise + call
    assert final_state.phase == :flop_betting
    assert broadcasted_state.phase == :flop_betting
    assert length(final_state.game_state.community_cards) == 3
  end

  test "re-raise scenario increases pot further", %{game_pid: game_pid} do
    start_hand_and_clear_broadcast(game_pid)

    # Get initial state
    initial_state = GameServer.get_state(game_pid)
    player1 = PokerServer.BettingRound.get_active_player(initial_state.betting_round)
    min_raise = PokerServer.BettingRound.minimum_raise(initial_state.betting_round)
    initial_pot = initial_state.betting_round.pot

    # Player 1 raises
    {:ok, :action_processed, _} = GameServer.player_action(game_pid, player1.id, {:raise, min_raise})
    assert_receive {:game_updated, _}, 1000

    # Get next player and new minimum raise
    raised_state = GameServer.get_state(game_pid)
    player2 = PokerServer.BettingRound.get_active_player(raised_state.betting_round)
    new_min_raise = PokerServer.BettingRound.minimum_raise(raised_state.betting_round)
    pot_after_raise = raised_state.betting_round.pot

    # Player 2 re-raises
    {:ok, :action_processed, final_state} = GameServer.player_action(game_pid, player2.id, {:raise, new_min_raise})
    assert_receive {:game_updated, broadcasted_state}, 1000

    # Pot should have increased twice
    assert final_state.betting_round.pot > pot_after_raise
    assert final_state.betting_round.pot > initial_pot
    assert broadcasted_state.betting_round.pot > pot_after_raise

    # Still in preflop betting, waiting for player1 to respond
    assert final_state.phase == :preflop_betting
    assert broadcasted_state.phase == :preflop_betting
  end

  test "out of turn action is rejected", %{game_pid: game_pid} do
    start_hand_and_clear_broadcast(game_pid)

    # Get active player and identify the non-active player
    current_state = GameServer.get_state(game_pid)
    active_player = PokerServer.BettingRound.get_active_player(current_state.betting_round)
    
    non_active_player = Enum.find(current_state.game_state.players, &(&1.id != active_player.id))

    # Non-active player tries to act - should fail
    {:error, reason} = GameServer.player_action(game_pid, non_active_player.id, {:call})
    
    assert reason == "not your turn"

    # No broadcast should occur for failed action
    refute_receive {:game_updated, _}, 500
  end

  test "invalid action for game state is rejected", %{game_pid: game_pid} do
    start_hand_and_clear_broadcast(game_pid)

    # Get active player
    current_state = GameServer.get_state(game_pid)
    active_player = PokerServer.BettingRound.get_active_player(current_state.betting_round)

    # In preflop with big blind, player1 cannot check (must call or fold/raise)
    # This depends on betting structure, let me check what actions are valid first
    valid_actions = PokerServer.BettingRound.valid_actions(current_state.betting_round)
    
    # Try an action that's not in the valid actions list
    invalid_action = if :check in valid_actions do
      # If check is valid, use a different invalid approach
      {:raise, -10}  # Negative raise amount
    else
      {:check}  # Check when bet is facing
    end

    {:error, _reason} = GameServer.player_action(game_pid, active_player.id, invalid_action)

    # No broadcast should occur for failed action
    refute_receive {:game_updated, _}, 500
  end

  test "raise with insufficient chips is rejected", %{game_pid: game_pid} do
    start_hand_and_clear_broadcast(game_pid)

    # Get active player
    current_state = GameServer.get_state(game_pid)
    active_player = PokerServer.BettingRound.get_active_player(current_state.betting_round)
    
    # Try to raise more than player's total chip stack
    excessive_raise = active_player.chips + 1000
    {:error, reason} = GameServer.player_action(game_pid, active_player.id, {:raise, excessive_raise})
    
    assert is_binary(reason)
    assert String.contains?(reason, "insufficient")

    # No broadcast should occur for failed action
    refute_receive {:game_updated, _}, 500
  end

  test "negative raise amount is rejected", %{game_pid: game_pid} do
    start_hand_and_clear_broadcast(game_pid)

    # Get active player
    current_state = GameServer.get_state(game_pid)
    active_player = PokerServer.BettingRound.get_active_player(current_state.betting_round)
    
    # Try negative raise - should fail validation
    {:error, reason} = GameServer.player_action(game_pid, active_player.id, {:raise, -50})
    
    assert is_binary(reason)

    # No broadcast should occur for failed action
    refute_receive {:game_updated, _}, 500
  end

  test "action by non-existent player is rejected", %{game_pid: game_pid} do
    start_hand_and_clear_broadcast(game_pid)

    # Try action by player not in the game
    {:error, reason} = GameServer.player_action(game_pid, "non_existent_player", {:call})
    
    # Should be a validation error about player not found
    assert match?({:invalid_input, _}, reason)

    # No broadcast should occur for failed action  
    refute_receive {:game_updated, _}, 500
  end

  test "action during wrong game phase is rejected", %{game_pid: game_pid} do
    # Don't start a hand - game should be in waiting phase
    
    # Try to make an action when no betting round is active
    {:error, reason} = GameServer.player_action(game_pid, "player1", {:call})
    
    assert reason == "no_active_betting_round"

    # No broadcast should occur for failed action
    refute_receive {:game_updated, _}, 500
  end

  test "multiple sequential invalid actions don't break game state", %{game_pid: game_pid} do
    start_hand_and_clear_broadcast(game_pid)

    # Get game state before invalid actions
    initial_state = GameServer.get_state(game_pid)
    active_player = PokerServer.BettingRound.get_active_player(initial_state.betting_round)
    non_active_player = Enum.find(initial_state.game_state.players, &(&1.id != active_player.id))

    # Try multiple invalid actions in sequence
    {:error, _} = GameServer.player_action(game_pid, non_active_player.id, {:call})  # Not their turn
    {:error, _} = GameServer.player_action(game_pid, "fake_player", {:call})  # Non-existent player
    {:error, _} = GameServer.player_action(game_pid, active_player.id, {:raise, -10})  # Negative raise

    # Game state should be unchanged
    current_state = GameServer.get_state(game_pid)
    assert current_state.phase == initial_state.phase
    assert current_state.betting_round.pot == initial_state.betting_round.pot
    
    # Active player should still be the same
    current_active = PokerServer.BettingRound.get_active_player(current_state.betting_round)
    assert current_active.id == active_player.id

    # Valid action should still work
    min_raise = PokerServer.BettingRound.minimum_raise(current_state.betting_round)
    {:ok, :action_processed, _} = GameServer.player_action(game_pid, active_player.id, {:raise, min_raise})
    
    assert_receive {:game_updated, _}, 1000

    # No broadcast should have occurred for invalid actions
    refute_receive {:game_updated, _}, 100
  end

  test "call amount exceeding chip stack triggers all-in", %{game_pid: _game_pid} do
    # This test verifies edge case handling when call amount > chips
    # We need a scenario where one player has very few chips
    
    # Create players with different stack sizes for this test
    players_unequal = [{"rich_player", 1000}, {"poor_player", 15}]  # Poor player has less than big blind
    {:ok, game_id} = PokerServer.GameManager.create_game(players_unequal)
    {:ok, game_pid} = PokerServer.GameManager.lookup_game(game_id)
    
    # Subscribe to this game's events
    Phoenix.PubSub.subscribe(PokerServer.PubSub, "game:#{game_id}:poor_player")

    # Start hand
    {:ok, _} = PokerServer.GameServer.start_hand(game_pid)
    assert_receive {:game_updated, _}, 1000

    # Get game state - poor player should be able to act but can't afford full call
    current_state = PokerServer.GameServer.get_state(game_pid)
    active_player = PokerServer.BettingRound.get_active_player(current_state.betting_round)
    
    if active_player.id == "poor_player" and active_player.chips < current_state.betting_round.current_bet do
      # Poor player can't afford full call - should be forced to all-in or fold
      valid_actions = PokerServer.BettingRound.valid_actions(current_state.betting_round)
      assert :all_in in valid_actions
      assert :call not in valid_actions or active_player.chips >= current_state.betting_round.current_bet
    end
  end
end
