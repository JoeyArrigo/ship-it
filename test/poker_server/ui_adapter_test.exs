defmodule PokerServer.UIAdapterTest do
  use ExUnit.Case, async: true
  doctest PokerServer.UIAdapter

  # We need to test the private function, so we'll use a test module
  # that exposes the function for testing
  defmodule TestableUIAdapter do
    # Copy the private function to make it testable
    def get_position_indicators(game_state, player_position) do
      player_count = length(game_state.players)
      indicators = []

      # Dealer button
      indicators = if player_position == game_state.button_position do
        [%{type: "dealer", label: "D", color: "yellow"} | indicators]
      else
        indicators
      end

      # Calculate blind positions based on player count
      {small_blind_position, big_blind_position} =
        if player_count == 2 do
          # Heads-up: button is small blind, other player is big blind
          big_blind_position = rem(game_state.button_position + 1, player_count)
          {game_state.button_position, big_blind_position}
        else
          # Multi-player: small blind is button + 1, big blind is button + 2
          small_blind_position = rem(game_state.button_position + 1, player_count)
          big_blind_position = rem(game_state.button_position + 2, player_count)
          {small_blind_position, big_blind_position}
        end

      # Small blind indicator
      indicators = if player_position == small_blind_position and
                      game_state.small_blind != nil and
                      game_state.small_blind > 0 do
        [%{type: "small_blind", label: "SB", color: "cyan"} | indicators]
      else
        indicators
      end

      # Big blind indicator
      indicators = if player_position == big_blind_position and
                      game_state.big_blind != nil and
                      game_state.big_blind > 0 do
        [%{type: "big_blind", label: "BB", color: "pink"} | indicators]
      else
        indicators
      end

      indicators
    end
  end

  describe "get_position_indicators/2" do
    test "returns dealer indicator for player at button position" do
      game_state = %{
        players: [%{position: 0}, %{position: 1}, %{position: 2}],
        button_position: 1,
        small_blind: 10,
        big_blind: 20
      }

      indicators = TestableUIAdapter.get_position_indicators(game_state, 1)

      assert %{type: "dealer", label: "D", color: "yellow"} in indicators
    end

    test "does not return dealer indicator for player not at button position" do
      game_state = %{
        players: [%{position: 0}, %{position: 1}, %{position: 2}],
        button_position: 1,
        small_blind: 10,
        big_blind: 20
      }

      indicators = TestableUIAdapter.get_position_indicators(game_state, 0)

      refute Enum.any?(indicators, fn indicator -> indicator.type == "dealer" end)
    end

    test "returns small blind indicator for correct position in multi-player game" do
      game_state = %{
        players: [%{position: 0}, %{position: 1}, %{position: 2}],
        button_position: 0,
        small_blind: 10,
        big_blind: 20
      }

      # Small blind should be at position 1 (button + 1)
      indicators = TestableUIAdapter.get_position_indicators(game_state, 1)

      assert %{type: "small_blind", label: "SB", color: "cyan"} in indicators
    end

    test "returns big blind indicator for correct position in multi-player game" do
      game_state = %{
        players: [%{position: 0}, %{position: 1}, %{position: 2}],
        button_position: 0,
        small_blind: 10,
        big_blind: 20
      }

      # Big blind should be at position 2 (button + 2)
      indicators = TestableUIAdapter.get_position_indicators(game_state, 2)

      assert %{type: "big_blind", label: "BB", color: "pink"} in indicators
    end

    test "handles position wrapping in multi-player game" do
      game_state = %{
        players: [%{position: 0}, %{position: 1}, %{position: 2}],
        button_position: 2,  # Last position
        small_blind: 10,
        big_blind: 20
      }

      # Small blind should wrap to position 0
      sb_indicators = TestableUIAdapter.get_position_indicators(game_state, 0)
      assert %{type: "small_blind", label: "SB", color: "cyan"} in sb_indicators

      # Big blind should wrap to position 1
      bb_indicators = TestableUIAdapter.get_position_indicators(game_state, 1)
      assert %{type: "big_blind", label: "BB", color: "pink"} in bb_indicators
    end

    test "returns multiple indicators for same player when applicable" do
      # In heads-up, button is also small blind
      game_state = %{
        players: [%{position: 0}, %{position: 1}],
        button_position: 0,
        small_blind: 10,
        big_blind: 20
      }

      indicators = TestableUIAdapter.get_position_indicators(game_state, 0)

      # Should have both dealer and small blind indicators
      assert %{type: "dealer", label: "D", color: "yellow"} in indicators
      assert %{type: "small_blind", label: "SB", color: "cyan"} in indicators
      assert length(indicators) == 2
    end

    test "heads-up game: button player gets dealer and small blind" do
      game_state = %{
        players: [%{position: 0}, %{position: 1}],
        button_position: 0,
        small_blind: 10,
        big_blind: 20
      }

      button_indicators = TestableUIAdapter.get_position_indicators(game_state, 0)

      assert %{type: "dealer", label: "D", color: "yellow"} in button_indicators
      assert %{type: "small_blind", label: "SB", color: "cyan"} in button_indicators
      refute Enum.any?(button_indicators, fn indicator -> indicator.type == "big_blind" end)
    end

    test "heads-up game: non-button player gets big blind only" do
      game_state = %{
        players: [%{position: 0}, %{position: 1}],
        button_position: 0,
        small_blind: 10,
        big_blind: 20
      }

      non_button_indicators = TestableUIAdapter.get_position_indicators(game_state, 1)

      assert %{type: "big_blind", label: "BB", color: "pink"} in non_button_indicators
      refute Enum.any?(non_button_indicators, fn indicator -> indicator.type == "dealer" end)
      refute Enum.any?(non_button_indicators, fn indicator -> indicator.type == "small_blind" end)
    end

    test "returns empty list when no special positions apply" do
      game_state = %{
        players: [%{position: 0}, %{position: 1}, %{position: 2}, %{position: 3}],
        button_position: 0,
        small_blind: 10,
        big_blind: 20
      }

      # Position 3 should have no special indicators
      indicators = TestableUIAdapter.get_position_indicators(game_state, 3)

      assert indicators == []
    end

    test "does not return blind indicators when blinds are nil" do
      game_state = %{
        players: [%{position: 0}, %{position: 1}, %{position: 2}],
        button_position: 0,
        small_blind: nil,
        big_blind: nil
      }

      # Position 1 would normally be small blind
      sb_indicators = TestableUIAdapter.get_position_indicators(game_state, 1)
      refute Enum.any?(sb_indicators, fn indicator -> indicator.type == "small_blind" end)

      # Position 2 would normally be big blind
      bb_indicators = TestableUIAdapter.get_position_indicators(game_state, 2)
      refute Enum.any?(bb_indicators, fn indicator -> indicator.type == "big_blind" end)
    end

    test "does not return blind indicators when blinds are zero" do
      game_state = %{
        players: [%{position: 0}, %{position: 1}, %{position: 2}],
        button_position: 0,
        small_blind: 0,
        big_blind: 0
      }

      # Position 1 would normally be small blind
      sb_indicators = TestableUIAdapter.get_position_indicators(game_state, 1)
      refute Enum.any?(sb_indicators, fn indicator -> indicator.type == "small_blind" end)

      # Position 2 would normally be big blind
      bb_indicators = TestableUIAdapter.get_position_indicators(game_state, 2)
      refute Enum.any?(bb_indicators, fn indicator -> indicator.type == "big_blind" end)
    end

    test "handles edge case with single player" do
      game_state = %{
        players: [%{position: 0}],
        button_position: 0,
        small_blind: 10,
        big_blind: 20
      }

      indicators = TestableUIAdapter.get_position_indicators(game_state, 0)

      # Single player should get dealer but blind logic should handle it gracefully
      assert %{type: "dealer", label: "D", color: "yellow"} in indicators
    end

    test "validates indicator structure" do
      game_state = %{
        players: [%{position: 0}, %{position: 1}, %{position: 2}],
        button_position: 0,
        small_blind: 10,
        big_blind: 20
      }

      indicators = TestableUIAdapter.get_position_indicators(game_state, 0)

      # Each indicator should have the required fields
      Enum.each(indicators, fn indicator ->
        assert Map.has_key?(indicator, :type)
        assert Map.has_key?(indicator, :label)
        assert Map.has_key?(indicator, :color)
        assert is_binary(indicator.type)
        assert is_binary(indicator.label)
        assert is_binary(indicator.color)
      end)
    end
  end
end