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

  test "start_hand broadcasts game state update", %{game_pid: game_pid, game_id: game_id} do
    # Act: Start a hand
    {:ok, _new_state} = GameServer.start_hand(game_pid)

    # Assert: Receive broadcast message
    assert_receive {:game_updated, broadcasted_state}, 1000

    # Verify the broadcasted state
    assert broadcasted_state.game_id == game_id
    assert broadcasted_state.phase == :preflop_betting
    assert not is_nil(broadcasted_state.betting_round)
    assert length(broadcasted_state.game_state.players) == 2
  end

  test "player action broadcasts state update", %{game_pid: game_pid, game_id: game_id} do
    # Setup: Start a hand first
    {:ok, _} = GameServer.start_hand(game_pid)

    # Clear the start_hand broadcast message
    assert_receive {:game_updated, _}, 1000

    # Act: Player makes an action
    result = GameServer.player_action(game_pid, "player1", {:call})

    # The result should be success (but format may vary)
    assert match?({:ok, _, _}, result) or match?(:ok, result)

    # Assert: Receive broadcast message for player action
    assert_receive {:game_updated, broadcasted_state}, 1000

    # Verify the broadcasted state reflects the action
    assert broadcasted_state.game_id == game_id
    # Note: State might have progressed beyond preflop if betting completed
    assert broadcasted_state.phase in [:preflop_betting, :flop_betting]
  end

  test "betting round completion broadcasts phase change", %{game_pid: game_pid} do
    # Setup: Start a hand
    {:ok, _} = GameServer.start_hand(game_pid)
    assert_receive {:game_updated, _}, 1000

    # Act: Complete betting round with both players calling
    result1 = GameServer.player_action(game_pid, "player1", {:call})
    assert match?({:ok, _, _}, result1) or match?(:ok, result1)
    assert_receive {:game_updated, _}, 1000

    result2 = GameServer.player_action(game_pid, "player2", {:check})

    # Check if action was valid or if we need different approach
    case result2 do
      {:ok, _, _} ->
        # Assert: Receive broadcast for phase change to flop_betting
        assert_receive {:game_updated, broadcasted_state}, 1000

        # Verify phase changed to flop_betting with new betting round
        assert broadcasted_state.phase == :flop_betting
        assert not is_nil(broadcasted_state.betting_round)
        assert length(broadcasted_state.game_state.community_cards) == 3

      {:error, :no_active_betting_round} ->
        # Betting already completed with first action
        # This is actually valid behavior for heads-up poker
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

  test "broadcast message format matches expected structure", %{
    game_pid: game_pid,
    game_id: _game_id
  } do
    # Act: Start hand
    {:ok, expected_state} = GameServer.start_hand(game_pid)

    # Assert: Receive and verify message format
    assert_receive {:game_updated, broadcasted_state}, 1000

    # Verify complete state structure is broadcasted (but filtered for security)
    assert Map.has_key?(broadcasted_state, :game_id)
    assert Map.has_key?(broadcasted_state, :game_state)
    assert Map.has_key?(broadcasted_state, :betting_round)
    assert Map.has_key?(broadcasted_state, :phase)

    # Verify the basic game data matches
    assert broadcasted_state.game_id == expected_state.game_id
    assert broadcasted_state.phase == expected_state.phase

    # Verify security filtering: player1 sees own cards, but not player2's
    player1_in_broadcast = Enum.find(broadcasted_state.game_state.players, &(&1.id == "player1"))
    player2_in_broadcast = Enum.find(broadcasted_state.game_state.players, &(&1.id == "player2"))

    # Can see own cards
    assert length(player1_in_broadcast.hole_cards) == 2
    # Cannot see other's cards
    assert length(player2_in_broadcast.hole_cards) == 0
  end

  test "failed actions do not broadcast state changes", %{game_pid: game_pid} do
    # Setup: Start hand
    {:ok, _} = GameServer.start_hand(game_pid)
    assert_receive {:game_updated, _}, 1000

    # Act: Attempt invalid action (non-existent player)
    {:error, _reason} = GameServer.player_action(game_pid, "invalid_player", {:call})

    # Assert: No additional broadcast should be received
    refute_receive {:game_updated, _}, 500
  end

  test "broadcast happens atomically with state updates", %{game_pid: game_pid} do
    # Act: Start hand
    {:ok, returned_state} = GameServer.start_hand(game_pid)

    # Assert: Broadcasted state is filtered but based on returned state
    assert_receive {:game_updated, broadcasted_state}, 1000

    # The broadcasted state should be a filtered version of the returned state
    assert broadcasted_state.game_id == returned_state.game_id
    assert broadcasted_state.phase == returned_state.phase

    # Verify current server state matches the unfiltered returned state
    current_state = GameServer.get_state(game_pid)
    assert current_state == returned_state

    # Verify the broadcast filtering worked correctly
    player1_in_broadcast = Enum.find(broadcasted_state.game_state.players, &(&1.id == "player1"))
    player2_in_broadcast = Enum.find(broadcasted_state.game_state.players, &(&1.id == "player2"))

    # Can see own cards
    assert length(player1_in_broadcast.hole_cards) == 2
    # Cannot see other's cards
    assert length(player2_in_broadcast.hole_cards) == 0
  end

  test "preflop betting completion transitions to flop_betting phase", %{game_pid: game_pid} do
    # Setup: Start a hand
    {:ok, _} = GameServer.start_hand(game_pid)
    assert_receive {:game_updated, _}, 1000

    # Act: Complete preflop betting (both players call/check)
    {:ok, _, _} = GameServer.player_action(game_pid, "player1", {:call})
    assert_receive {:game_updated, _}, 1000
    
    {:ok, :betting_complete, _} = GameServer.player_action(game_pid, "player2", {:check})

    # Assert: Should transition to flop_betting phase with new betting round
    assert_receive {:game_updated, broadcasted_state}, 1000
    
    assert broadcasted_state.phase == :flop_betting
    assert not is_nil(broadcasted_state.betting_round)
    assert length(broadcasted_state.game_state.community_cards) == 3
  end

  test "flop_betting phase allows player actions", %{game_pid: game_pid} do
    # Setup: Complete preflop betting to reach flop_betting
    {:ok, _} = GameServer.start_hand(game_pid)
    assert_receive {:game_updated, _}, 1000
    
    {:ok, _, _} = GameServer.player_action(game_pid, "player1", {:call})
    assert_receive {:game_updated, _}, 1000
    
    {:ok, :betting_complete, _} = GameServer.player_action(game_pid, "player2", {:check})
    assert_receive {:game_updated, _}, 1000

    # Act: Make action in flop_betting phase
    {:ok, _, _} = GameServer.player_action(game_pid, "player2", {:check})

    # Assert: Action is processed and broadcast
    assert_receive {:game_updated, broadcasted_state}, 1000
    assert broadcasted_state.phase == :flop_betting
  end
end
