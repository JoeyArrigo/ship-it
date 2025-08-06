defmodule PokerServer.InputValidator do
  @moduledoc """
  Comprehensive input validation for the PokerServer application.
  
  Provides validation functions to ensure data integrity, prevent crashes,
  and protect against malicious input across all poker server operations.
  """

  @doc """
  Validates a list of players for game creation.
  
  Ensures:
  - Player list is not empty
  - No duplicate player IDs
  - All players have valid chip amounts (positive integers)
  - Player count is within reasonable limits
  """
  def validate_players(players) when is_list(players) do
    cond do
      length(players) == 0 ->
        {:error, :empty_player_list}
      
      length(players) > 10 ->
        {:error, :too_many_players}
      
      length(players) < 2 ->
        {:error, :insufficient_players}
      
      true ->
        players
        |> validate_player_list()
        |> validate_unique_player_ids()
    end
  end
  
  def validate_players(_), do: {:error, :invalid_player_list_format}

  @doc """
  Validates an individual player tuple format.
  
  Expects {player_id, chips} where:
  - player_id is not nil, empty string, or invalid type
  - chips is positive integer
  """
  def validate_player_tuple({player_id, chips}) do
    with :ok <- validate_player_id(player_id),
         :ok <- validate_chip_amount(chips) do
      :ok
    end
  end
  
  def validate_player_tuple(_), do: {:error, :invalid_player_tuple_format}

  @doc """
  Validates a player ID for existence and format.
  
  Player IDs must be:
  - Not nil
  - Not empty string
  - Valid type (string, integer, or atom)
  """
  def validate_player_id(nil), do: {:error, :nil_player_id}
  def validate_player_id(""), do: {:error, :empty_player_id}
  def validate_player_id(id) when is_binary(id) or is_integer(id) or is_atom(id), do: :ok
  def validate_player_id(_), do: {:error, :invalid_player_id_type}

  @doc """
  Validates chip amounts for non-negative values.
  
  Chip amounts must be:
  - Positive integers
  - Not nil, floats, or strings
  - Within reasonable limits to prevent overflow
  """
  def validate_chip_amount(chips) when is_integer(chips) and chips > 0 and chips <= 1_000_000, do: :ok
  def validate_chip_amount(chips) when is_integer(chips) and chips <= 0, do: {:error, :non_positive_chips}
  def validate_chip_amount(chips) when is_integer(chips), do: {:error, :chips_too_large}
  def validate_chip_amount(nil), do: {:error, :nil_chip_amount}
  def validate_chip_amount(_), do: {:error, :invalid_chip_type}

  @doc """
  Validates betting actions for proper format and values.
  
  Actions must be valid tuples like:
  - {:fold}
  - {:call}  
  - {:check}
  - {:raise, amount} where amount is positive
  - {:all_in}
  """
  def validate_action({:fold}), do: :ok
  def validate_action({:call}), do: :ok
  def validate_action({:check}), do: :ok
  def validate_action({:all_in}), do: :ok
  def validate_action({:raise, amount}) when is_integer(amount) and amount > 0, do: :ok
  def validate_action({:raise, amount}) when is_integer(amount), do: {:error, :invalid_raise_amount}
  def validate_action({:raise, _}), do: {:error, :invalid_raise_type}
  def validate_action(action) when is_tuple(action), do: {:error, :unknown_action}
  def validate_action(_), do: {:error, :invalid_action_format}

  @doc """
  Validates that a player exists in a game's player list.
  """
  def validate_player_exists(player_id, players) when is_list(players) do
    if Enum.any?(players, &(&1.id == player_id)) do
      :ok
    else
      {:error, :player_not_found}
    end
  end
  
  def validate_player_exists(_, _), do: {:error, :invalid_players_list}

  @doc """
  Validates position/index values are within bounds.
  """
  def validate_position(position, max_position) when is_integer(position) and position >= 0 and position < max_position do
    :ok
  end
  
  def validate_position(position, _) when is_integer(position), do: {:error, :position_out_of_bounds}
  def validate_position(_, _), do: {:error, :invalid_position_type}

  @doc """
  Validates game state is suitable for operations.
  
  Checks:
  - Game has players
  - Game state is valid
  - No corrupted data
  """
  def validate_game_state(%{players: players} = _game_state) when is_list(players) and length(players) > 0 do
    :ok
  end
  
  def validate_game_state(%{players: []}), do: {:error, :no_players_in_game}
  def validate_game_state(%{players: players}) when not is_list(players), do: {:error, :corrupted_players_list}
  def validate_game_state(_), do: {:error, :invalid_game_state}

  # Private helper functions

  defp validate_player_list(players) do
    case Enum.find(players, fn player -> validate_player_tuple(player) != :ok end) do
      nil -> {:ok, players}
      invalid_player -> {:error, {:invalid_player, invalid_player}}
    end
  end

  defp validate_unique_player_ids({:ok, players}) do
    player_ids = Enum.map(players, &elem(&1, 0))
    unique_ids = Enum.uniq(player_ids)
    
    if length(player_ids) == length(unique_ids) do
      {:ok, players}
    else
      {:error, :duplicate_player_ids}
    end
  end
  
  defp validate_unique_player_ids(error), do: error

  @doc """
  Helper function to safely apply validation and return standardized errors.
  """
  def safe_validate(validation_fn) do
    try do
      validation_fn.()
    rescue
      error -> {:error, {:validation_exception, error}}
    end
  end
end