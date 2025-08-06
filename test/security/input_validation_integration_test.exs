defmodule PokerServer.InputValidationIntegrationTest do
  use ExUnit.Case
  alias PokerServer.{GameManager, GameServer}

  describe "security against malicious inputs" do
    test "prevents game creation with negative chip amounts" do
      # These malicious inputs should be rejected
      malicious_players = [
        {"player1", -1000},  # Negative chips
        {"player2", 1500}
      ]
      
      result = GameManager.create_game(malicious_players)
      assert {:error, {:invalid_input, {:invalid_player, _}}} = result
    end

    test "prevents game creation with zero chip amounts" do
      malicious_players = [
        {"player1", 0},      # Zero chips
        {"player2", 1500}
      ]
      
      result = GameManager.create_game(malicious_players)
      assert {:error, {:invalid_input, {:invalid_player, _}}} = result
    end

    test "prevents game creation with invalid chip types" do
      malicious_players = [
        {"player1", "1500"},  # String instead of integer
        {"player2", 1500}
      ]
      
      result = GameManager.create_game(malicious_players)
      assert {:error, {:invalid_input, {:invalid_player, _}}} = result
    end

    test "prevents game creation with nil player IDs" do
      malicious_players = [
        {nil, 1500},         # Nil player ID
        {"player2", 1500}
      ]
      
      result = GameManager.create_game(malicious_players)
      assert {:error, {:invalid_input, {:invalid_player, _}}} = result
    end

    test "prevents game creation with empty player IDs" do
      malicious_players = [
        {"", 1500},          # Empty player ID
        {"player2", 1500}
      ]
      
      result = GameManager.create_game(malicious_players)
      assert {:error, {:invalid_input, {:invalid_player, _}}} = result
    end

    test "prevents game creation with duplicate player IDs" do
      malicious_players = [
        {"player1", 1500},
        {"player1", 1000}    # Duplicate ID
      ]
      
      result = GameManager.create_game(malicious_players)
      assert {:error, {:invalid_input, :duplicate_player_ids}} = result
    end

    test "prevents game creation with too many players" do
      malicious_players = for i <- 1..15, do: {"player#{i}", 1000}
      
      result = GameManager.create_game(malicious_players)
      assert {:error, {:invalid_input, :too_many_players}} = result
    end

    test "prevents game creation with insufficient players" do
      malicious_players = [{"player1", 1500}]  # Only one player
      
      result = GameManager.create_game(malicious_players)
      assert {:error, {:invalid_input, :insufficient_players}} = result
    end

    test "prevents game creation with empty player list" do
      malicious_players = []
      
      result = GameManager.create_game(malicious_players)
      assert {:error, {:invalid_input, :empty_player_list}} = result
    end

    test "prevents player actions with nil player ID" do
      # Create a valid game first
      players = [{"player1", 1500}, {"player2", 1500}]
      {:ok, game_id} = GameManager.create_game(players)
      
      # Attempt malicious action
      result = GameManager.player_action(game_id, nil, {:fold})
      assert {:error, {:invalid_input, :nil_player_id}} = result
    end

    test "prevents player actions with empty player ID" do
      players = [{"player1", 1500}, {"player2", 1500}]
      {:ok, game_id} = GameManager.create_game(players)
      
      result = GameManager.player_action(game_id, "", {:fold})
      assert {:error, {:invalid_input, :empty_player_id}} = result
    end

    test "prevents player actions with invalid action format" do
      players = [{"player1", 1500}, {"player2", 1500}]
      {:ok, game_id} = GameManager.create_game(players)
      
      # Invalid action formats
      assert {:error, {:invalid_input, :invalid_action_format}} = 
        GameManager.player_action(game_id, "player1", "fold")
      
      assert {:error, {:invalid_input, :invalid_action_format}} = 
        GameManager.player_action(game_id, "player1", nil)
      
      assert {:error, {:invalid_input, :unknown_action}} = 
        GameManager.player_action(game_id, "player1", {:invalid_action})
    end

    test "prevents player actions with invalid raise amounts" do
      players = [{"player1", 1500}, {"player2", 1500}]
      {:ok, game_id} = GameManager.create_game(players)
      
      # Negative raise
      assert {:error, {:invalid_input, :invalid_raise_amount}} = 
        GameManager.player_action(game_id, "player1", {:raise, -100})
      
      # Zero raise  
      assert {:error, {:invalid_input, :invalid_raise_amount}} = 
        GameManager.player_action(game_id, "player1", {:raise, 0})
      
      # Invalid raise type
      assert {:error, {:invalid_input, :invalid_raise_type}} = 
        GameManager.player_action(game_id, "player1", {:raise, "100"})
    end

    test "prevents actions from non-existent players" do
      players = [{"player1", 1500}, {"player2", 1500}]
      {:ok, game_id} = GameManager.create_game(players)
      {:ok, game_pid} = GameManager.lookup_game(game_id)
      
      # Start hand to enable betting
      GameServer.start_hand(game_pid)
      
      # Try action from non-existent player
      result = GameServer.player_action(game_pid, "nonexistent", {:fold})
      assert {:error, {:invalid_input, :player_not_found}} = result
    end

    test "system remains stable after validation rejections" do
      # Try many malicious inputs in sequence
      malicious_attempts = [
        [{"player1", -1000}, {"player2", 1500}],
        [{nil, 1500}, {"player2", 1500}],
        [{"", 1500}, {"player2", 1500}],
        [{"player1", "invalid"}, {"player2", 1500}],
        [],  # Empty list
        for(i <- 1..15, do: {"player#{i}", 1000})  # Too many players
      ]
      
      # All should be rejected
      for malicious_input <- malicious_attempts do
        result = GameManager.create_game(malicious_input)
        assert {:error, {:invalid_input, _reason}} = result
      end
      
      # System should still work for valid input
      valid_players = [{"player1", 1500}, {"player2", 1500}]
      assert {:ok, _game_id} = GameManager.create_game(valid_players)
    end

    test "validation errors are descriptive and safe" do
      # Errors should not leak internal system information
      result = GameManager.create_game([{"player1", -100}, {"player2", 1500}])
      
      case result do
        {:error, {:invalid_input, {:invalid_player, _}}} ->
          # Error should be descriptive but not leak internals - this is the expected format
          :ok
        _ ->
          flunk("Expected validation error with invalid_player format")
      end
    end
  end

  describe "performance under malicious load" do
    test "validation does not cause significant performance degradation" do
      # Measure validation performance
      {time_microseconds, _result} = :timer.tc(fn ->
        # Try 1000 validation attempts
        for _i <- 1..1000 do
          GameManager.create_game([{"player1", -100}, {"player2", 1500}])
        end
      end)
      
      # Should complete quickly (under 1 second)
      assert time_microseconds < 1_000_000, "Validation taking too long: #{time_microseconds} microseconds"
    end
  end
end