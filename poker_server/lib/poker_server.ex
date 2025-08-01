defmodule PokerServer do
  @moduledoc """
  Main API for the PokerServer application.
  
  Provides functions to create games, manage players, and process actions
  in real-time multiplayer poker games.
  """

  alias PokerServer.GameManager

  @doc """
  Create a new poker game with the given players.
  
  ## Parameters
  - players: List of {player_id, starting_chips} tuples
  
  Returns {:ok, game_id} where game_id is a unique identifier for the game.
  """
  def create_game(players) when is_list(players) do
    GameManager.create_game(players)
  end

  @doc """
  Get the current state of a game.
  
  Returns the current game state and phase information.
  """
  def get_game_state(game_id) do
    GameManager.get_game_state(game_id)
  end

  @doc """
  Process a player action in a game.
  
  ## Parameters
  - game_id: The game identifier
  - player_id: The player making the action  
  - action: The action tuple, e.g., {:fold}, {:call}, {:raise, 40}
  """
  def player_action(game_id, player_id, action) do
    GameManager.player_action(game_id, player_id, action)
  end

  @doc """
  Start a hand in an existing game.
  """
  def start_hand(game_id) do
    PokerServer.GameRegistry
    |> Registry.lookup(game_id)
    |> do_start_hand()
  end

  # Pattern match on successful Registry lookup
  defp do_start_hand([{pid, _}]) do
    PokerServer.GameServer.start_hand(pid)
  end

  # Pattern match on game not found
  defp do_start_hand([]) do
    {:error, :game_not_found}
  end

  @doc """
  List all active games.
  
  Returns a list of game IDs for all currently active games.
  """
  def list_games do
    GameManager.list_games()
  end

end
