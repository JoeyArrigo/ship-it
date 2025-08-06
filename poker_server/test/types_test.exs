defmodule PokerServer.TypesTest do
  use ExUnit.Case
  alias PokerServer.Types

  describe "validation functions" do
    test "validate_server_phase! accepts valid phases" do
      for phase <- Types.all_server_phases() do
        assert Types.validate_server_phase!(phase) == phase
      end
    end

    test "validate_server_phase! rejects invalid phases" do
      assert_raise ArgumentError, ~r/Invalid server phase: :invalid/, fn ->
        Types.validate_server_phase!(:invalid)
      end
    end

    test "validate_game_state_phase! accepts valid phases" do
      for phase <- Types.all_game_state_phases() do
        assert Types.validate_game_state_phase!(phase) == phase
      end
    end

    test "validate_betting_round_type! accepts valid types" do
      for type <- Types.all_betting_round_types() do
        assert Types.validate_betting_round_type!(type) == type
      end
    end

    test "validate_player_action_type! accepts valid actions" do
      for action <- Types.all_player_action_types() do
        assert Types.validate_player_action_type!(action) == action
      end
    end
  end

  describe "soft validation functions" do
    test "valid_server_phase? returns boolean" do
      assert Types.valid_server_phase?(:preflop_betting) == true
      assert Types.valid_server_phase?(:invalid) == false
    end

    test "valid_game_state_phase? returns boolean" do
      assert Types.valid_game_state_phase?(:preflop) == true
      assert Types.valid_game_state_phase?(:invalid) == false
    end
  end

  describe "error messages" do
    test "error messages are consistent strings" do
      assert is_binary(Types.error_not_your_turn())
      assert is_binary(Types.error_invalid_action())
      assert is_binary(Types.error_no_active_betting_round())
    end

    test "error message functions work" do
      assert Types.error_insufficient_chips(100, 50) == "insufficient chips to call: need 100, have 50"
      assert Types.error_below_minimum_raise(50, 100) == "raise amount 50 is below minimum raise of 100"
    end
  end

  describe "phase transitions" do
    test "betting_round_to_game_state_phase maps correctly" do
      assert Types.betting_round_to_game_state_phase(:preflop) == :preflop
      assert Types.betting_round_to_game_state_phase(:flop) == :flop
      assert Types.betting_round_to_game_state_phase(:turn) == :turn
      assert Types.betting_round_to_game_state_phase(:river) == :river
    end

    test "betting_round_to_server_phase maps correctly" do
      assert Types.betting_round_to_server_phase(:preflop) == :preflop_betting
      assert Types.betting_round_to_server_phase(:flop) == :flop_betting
      assert Types.betting_round_to_server_phase(:turn) == :turn_betting
      assert Types.betting_round_to_server_phase(:river) == :river_betting
    end

    test "valid_game_state_transition? validates transitions" do
      assert Types.valid_game_state_transition?(:preflop, :flop) == true
      assert Types.valid_game_state_transition?(:flop, :turn) == true
      assert Types.valid_game_state_transition?(:turn, :river) == true
      assert Types.valid_game_state_transition?(:river, :hand_complete) == true

      # Invalid transitions
      assert Types.valid_game_state_transition?(:flop, :preflop) == false
      assert Types.valid_game_state_transition?(:waiting_for_players, :flop) == false
    end

    test "valid_server_transition? validates transitions" do
      assert Types.valid_server_transition?(:preflop_betting, :flop_betting) == true
      assert Types.valid_server_transition?(:flop_betting, :turn_betting) == true
      assert Types.valid_server_transition?(:turn_betting, :river_betting) == true

      # Invalid transitions
      assert Types.valid_server_transition?(:flop_betting, :preflop_betting) == false
    end
  end

  describe "guards" do
    import Types

    test "guards work at compile time" do
      # These should compile without issues
      assert is_game_state_phase(:preflop)
      assert is_server_phase(:preflop_betting)
      assert is_betting_round_type(:flop)
      assert is_player_action_type(:fold)

      refute is_game_state_phase(:invalid)
      refute is_server_phase(:invalid)
    end
  end
end