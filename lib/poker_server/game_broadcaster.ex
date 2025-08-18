defmodule PokerServer.GameBroadcaster do
  @moduledoc """
  Service responsible for broadcasting game state changes to connected players.

  Handles player-specific filtering and PubSub communication, removing the
  architectural dependency between GameServer (business logic) and UIAdapter
  (presentation layer).
  """

  alias PokerServer.UIAdapter
  alias Phoenix.PubSub

  @doc """
  Broadcast game state change to all players with appropriate filtering.

  Each player receives a filtered view that hides other players' hole cards
  and includes only the information they should see.
  """
  @spec broadcast_state_change(String.t(), map()) :: :ok
  def broadcast_state_change(game_id, game_server_state) do
    game_server_state.game_state.players
    |> Enum.each(fn player ->
      broadcast_to_player(game_id, game_server_state, player.id)
    end)

    :ok
  end

  @doc """
  Broadcast game state to a specific player with appropriate filtering.
  """
  @spec broadcast_to_player(String.t(), map(), String.t()) :: :ok
  def broadcast_to_player(game_id, game_server_state, player_id) do
    filtered_view = UIAdapter.get_broadcast_player_view(game_server_state, player_id)

    PubSub.broadcast(
      PokerServer.PubSub,
      "game:#{game_id}:#{player_id}",
      {:game_updated, filtered_view}
    )

    :ok
  end

  @doc """
  Broadcast a custom message to all players in a game.
  """
  @spec broadcast_message(String.t(), term()) :: :ok
  def broadcast_message(game_id, message) do
    PubSub.broadcast(
      PokerServer.PubSub,
      "game:#{game_id}",
      message
    )

    :ok
  end

  @doc """
  Broadcast a custom message to a specific player.
  """
  @spec broadcast_to_player_message(String.t(), String.t(), term()) :: :ok
  def broadcast_to_player_message(game_id, player_id, message) do
    PubSub.broadcast(
      PokerServer.PubSub,
      "game:#{game_id}:#{player_id}",
      message
    )

    :ok
  end
end
