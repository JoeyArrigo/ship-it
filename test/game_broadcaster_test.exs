defmodule PokerServer.GameBroadcasterTest do
  use ExUnit.Case, async: true
  alias PokerServer.{GameBroadcaster, GameState, Player}
  alias Phoenix.PubSub

  setup do
    # Create a mock game server state for testing
    players = [
      %Player{id: "player1", chips: 1000, position: 0, hole_cards: []},
      %Player{id: "player2", chips: 1000, position: 1, hole_cards: []}
    ]

    game_state = GameState.new(players)

    game_server_state = %{
      game_id: "test_game",
      game_state: game_state,
      betting_round: nil,
      phase: :waiting_to_start,
      folded_players: MapSet.new()
    }

    %{game_server_state: game_server_state}
  end

  describe "broadcast_state_change/2" do
    test "broadcasts to all players in the game", %{game_server_state: state} do
      game_id = "test_broadcast"

      # Subscribe to player-specific channels
      PubSub.subscribe(PokerServer.PubSub, "game:#{game_id}:player1")
      PubSub.subscribe(PokerServer.PubSub, "game:#{game_id}:player2")

      # Broadcast state change
      assert :ok = GameBroadcaster.broadcast_state_change(game_id, state)

      # Both players should receive broadcasts
      assert_receive {:game_updated, player1_view}, 1000
      assert_receive {:game_updated, player2_view}, 1000
      # Both should be valid game views
      assert is_map(player1_view)
      assert is_map(player2_view)
      assert Map.has_key?(player1_view, :game_id)
      assert Map.has_key?(player2_view, :game_id)
    end

    test "returns :ok on successful broadcast", %{game_server_state: state} do
      result = GameBroadcaster.broadcast_state_change("test_game", state)
      assert result == :ok
    end
  end

  describe "broadcast_to_player/3" do
    test "broadcasts to specific player only", %{game_server_state: state} do
      game_id = "test_player_broadcast"

      # Subscribe to both channels
      PubSub.subscribe(PokerServer.PubSub, "game:#{game_id}:player1")
      PubSub.subscribe(PokerServer.PubSub, "game:#{game_id}:player2")

      # Broadcast to player1 only
      assert :ok = GameBroadcaster.broadcast_to_player(game_id, state, "player1")

      # Only player1 should receive the broadcast
      assert_receive {:game_updated, player1_view}, 1000
      refute_receive {:game_updated, _}, 500
      assert is_map(player1_view)
      assert Map.has_key?(player1_view, :game_id)
    end

    test "returns :ok on successful broadcast", %{game_server_state: state} do
      result = GameBroadcaster.broadcast_to_player("test_game", state, "player1")
      assert result == :ok
    end
  end

  describe "broadcast_message/2" do
    test "broadcasts custom message to game channel" do
      game_id = "test_custom_message"
      custom_message = {:custom_event, "test_data"}

      # Subscribe to general game channel
      PubSub.subscribe(PokerServer.PubSub, "game:#{game_id}")

      # Broadcast custom message
      assert :ok = GameBroadcaster.broadcast_message(game_id, custom_message)
      # Should receive the custom message
      assert_receive {:custom_event, "test_data"}, 1000
    end

    test "returns :ok on successful broadcast" do
      result = GameBroadcaster.broadcast_message("test_game", {:test, "message"})
      assert result == :ok
    end
  end

  describe "broadcast_to_player_message/3" do
    test "broadcasts custom message to specific player" do
      game_id = "test_player_message"
      player_id = "player1"
      custom_message = {:player_notification, "your turn"}

      # Subscribe to player-specific channel
      PubSub.subscribe(PokerServer.PubSub, "game:#{game_id}:#{player_id}")

      # Broadcast custom message to player
      assert :ok = GameBroadcaster.broadcast_to_player_message(game_id, player_id, custom_message)
      # Should receive the custom message
      assert_receive {:player_notification, "your turn"}, 1000
    end

    test "returns :ok on successful broadcast" do
      result =
        GameBroadcaster.broadcast_to_player_message("test_game", "player1", {:test, "message"})

      assert result == :ok
    end
  end

  describe "integration with UIAdapter filtering" do
    test "player-specific filtering works correctly", %{game_server_state: base_state} do
      game_id = "test_filtering"

      # Add hole cards to players to test filtering
      player1_with_cards = %{
        Enum.find(base_state.game_state.players, &(&1.id == "player1"))
        | hole_cards: [%{rank: :ace, suit: :spades}, %{rank: :king, suit: :hearts}]
      }

      player2_with_cards = %{
        Enum.find(base_state.game_state.players, &(&1.id == "player2"))
        | hole_cards: [%{rank: :queen, suit: :diamonds}, %{rank: :jack, suit: :clubs}]
      }

      updated_players = [player1_with_cards, player2_with_cards]
      updated_game_state = %{base_state.game_state | players: updated_players}
      state_with_cards = %{base_state | game_state: updated_game_state}

      # Subscribe to player1's channel
      PubSub.subscribe(PokerServer.PubSub, "game:#{game_id}:player1")

      # Broadcast state change
      GameBroadcaster.broadcast_state_change(game_id, state_with_cards)

      # Player1 should receive filtered view
      assert_receive {:game_updated, filtered_view}, 1000

      # Find players in the filtered view
      player1_in_view = Enum.find(filtered_view.game_state.players, &(&1.id == "player1"))
      player2_in_view = Enum.find(filtered_view.game_state.players, &(&1.id == "player2"))
      # Player1 should see their own cards but not player2's
      assert length(player1_in_view.hole_cards) == 2
      assert length(player2_in_view.hole_cards) == 0
    end
  end
end
