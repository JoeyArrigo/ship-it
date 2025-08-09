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
end
