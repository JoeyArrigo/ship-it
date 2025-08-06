defmodule PokerServer.Types do
  @moduledoc """
  Centralized type definitions and validation for the poker server.
  
  This module provides:
  - @type specifications for Dialyzer static analysis
  - Validation functions with clear error messages
  - Centralized lists of valid values
  - Guards for compile-time validation
  """

  # Game state phases - represents the current stage of a poker hand
  @type game_state_phase :: :waiting_for_players | :preflop | :flop | :turn | :river | :hand_complete

  # GameServer phases - represents what the server is currently doing
  @type server_phase :: :waiting_to_start | :preflop_betting | :flop_betting | :turn_betting | :river_betting

  # Betting round types - the current betting street
  @type betting_round_type :: :preflop | :flop | :turn | :river

  # Player actions - what a player can do during betting
  @type player_action :: :fold | :call | :check | {:raise, pos_integer()} | :all_in

  # Player action types (for validation)
  @type player_action_type :: :fold | :call | :check | :raise | :all_in

  # Error messages for consistency
  @error_not_your_turn "not your turn"
  @error_invalid_action "invalid action"
  @error_no_active_betting_round "no_active_betting_round"

  # Guards for compile-time validation
  defguard is_game_state_phase(phase) when phase in [:waiting_for_players, :preflop, :flop, :turn, :river, :hand_complete]
  
  defguard is_server_phase(phase) when phase in [:waiting_to_start, :preflop_betting, :flop_betting, :turn_betting, :river_betting]
  
  defguard is_betting_round_type(type) when type in [:preflop, :flop, :turn, :river]
  
  defguard is_player_action_type(action) when action in [:fold, :call, :check, :raise, :all_in]

  # Lists of valid values
  def all_game_state_phases, do: [:waiting_for_players, :preflop, :flop, :turn, :river, :hand_complete]
  
  def all_server_phases, do: [:waiting_to_start, :preflop_betting, :flop_betting, :turn_betting, :river_betting]
  
  def all_betting_round_types, do: [:preflop, :flop, :turn, :river]
  
  def all_player_action_types, do: [:fold, :call, :check, :raise, :all_in]

  # Validation functions with clear error messages
  
  @doc """
  Validates a game state phase, raising ArgumentError with helpful message if invalid.
  """
  @spec validate_game_state_phase!(term()) :: game_state_phase()
  def validate_game_state_phase!(phase) when is_game_state_phase(phase), do: phase
  
  def validate_game_state_phase!(invalid_phase) do
    raise ArgumentError, """
    Invalid game state phase: #{inspect(invalid_phase)}
    
    Valid phases: #{inspect(all_game_state_phases())}
    
    Game state phases represent the current stage of a poker hand.
    """
  end

  @doc """
  Validates a server phase, raising ArgumentError with helpful message if invalid.
  """
  @spec validate_server_phase!(term()) :: server_phase()
  def validate_server_phase!(phase) when is_server_phase(phase), do: phase
  
  def validate_server_phase!(invalid_phase) do
    raise ArgumentError, """
    Invalid server phase: #{inspect(invalid_phase)}
    
    Valid phases: #{inspect(all_server_phases())}
    
    Server phases represent what the GameServer is currently doing.
    """
  end

  @doc """
  Validates a betting round type, raising ArgumentError with helpful message if invalid.
  """
  @spec validate_betting_round_type!(term()) :: betting_round_type()
  def validate_betting_round_type!(type) when is_betting_round_type(type), do: type
  
  def validate_betting_round_type!(invalid_type) do
    raise ArgumentError, """
    Invalid betting round type: #{inspect(invalid_type)}
    
    Valid types: #{inspect(all_betting_round_types())}
    
    Betting round types represent the current betting street.
    """
  end

  @doc """
  Validates a player action type, raising ArgumentError with helpful message if invalid.
  """
  @spec validate_player_action_type!(term()) :: player_action_type()
  def validate_player_action_type!(action_type) when is_player_action_type(action_type), do: action_type
  
  def validate_player_action_type!(invalid_type) do
    raise ArgumentError, """
    Invalid player action type: #{inspect(invalid_type)}
    
    Valid action types: #{inspect(all_player_action_types())}
    
    Player action types represent what a player can do during betting.
    """
  end

  # Soft validation functions (return {:ok, value} | {:error, reason})
  
  @spec valid_game_state_phase?(term()) :: boolean()
  def valid_game_state_phase?(phase), do: phase in all_game_state_phases()
  
  @spec valid_server_phase?(term()) :: boolean()
  def valid_server_phase?(phase), do: phase in all_server_phases()
  
  @spec valid_betting_round_type?(term()) :: boolean()
  def valid_betting_round_type?(type), do: type in all_betting_round_types()
  
  @spec valid_player_action_type?(term()) :: boolean()
  def valid_player_action_type?(action_type), do: action_type in all_player_action_types()

  # Error message constants
  
  def error_not_your_turn, do: @error_not_your_turn
  def error_invalid_action, do: @error_invalid_action  
  def error_no_active_betting_round, do: @error_no_active_betting_round

  @doc """
  Formats insufficient chips error message.
  """
  def error_insufficient_chips(needed, have) do
    "insufficient chips to call: need #{needed}, have #{have}"
  end

  @doc """
  Formats below minimum raise error message.
  """
  def error_below_minimum_raise(amount, minimum) do
    "raise amount #{amount} is below minimum raise of #{minimum}"
  end

  @doc """
  Formats insufficient chips for raise error message.
  """
  def error_insufficient_chips_for_raise(needed, have) do
    "insufficient chips: need #{needed}, have #{have}"
  end

  # Phase transition mapping functions
  
  @doc """
  Maps betting round types to their corresponding game state phases.
  """
  @spec betting_round_to_game_state_phase(betting_round_type()) :: game_state_phase()
  def betting_round_to_game_state_phase(:preflop), do: :preflop
  def betting_round_to_game_state_phase(:flop), do: :flop
  def betting_round_to_game_state_phase(:turn), do: :turn
  def betting_round_to_game_state_phase(:river), do: :river

  @doc """
  Maps betting round types to their corresponding server phases.
  """
  @spec betting_round_to_server_phase(betting_round_type()) :: server_phase()
  def betting_round_to_server_phase(:preflop), do: :preflop_betting
  def betting_round_to_server_phase(:flop), do: :flop_betting
  def betting_round_to_server_phase(:turn), do: :turn_betting
  def betting_round_to_server_phase(:river), do: :river_betting

  @doc """
  Validates that a phase transition is legal.
  """
  @spec valid_game_state_transition?(game_state_phase(), game_state_phase()) :: boolean()
  def valid_game_state_transition?(from_phase, to_phase) do
    valid_transitions = %{
      :waiting_for_players => [:preflop],
      :preflop => [:flop, :hand_complete],
      :flop => [:turn, :hand_complete],
      :turn => [:river, :hand_complete],
      :river => [:hand_complete],
      :hand_complete => [:waiting_for_players, :preflop]
    }
    
    to_phase in Map.get(valid_transitions, from_phase, [])
  end

  @doc """
  Validates that a server phase transition is legal.
  """
  @spec valid_server_transition?(server_phase(), server_phase()) :: boolean()
  def valid_server_transition?(from_phase, to_phase) do
    valid_transitions = %{
      :waiting_to_start => [:preflop_betting],
      :preflop_betting => [:flop_betting, :waiting_to_start],
      :flop_betting => [:turn_betting, :waiting_to_start],
      :turn_betting => [:river_betting, :waiting_to_start],
      :river_betting => [:waiting_to_start]
    }
    
    to_phase in Map.get(valid_transitions, from_phase, [])
  end
end