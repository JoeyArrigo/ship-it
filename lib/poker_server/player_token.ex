defmodule PokerServer.PlayerToken do
  @moduledoc """
  Secure player token generation and validation for poker games.

  Tokens contain {game_id, player_name} signed with Phoenix.Token.
  Tokens are valid until tournament completes (no time expiration).
  """

  @salt "player_game_token"

  defp get_secret_key_base do
    PokerServerWeb.Endpoint.config(:secret_key_base)
  end

  @doc """
  Generates a secure token for a player in a specific game.

  ## Parameters
  - game_id: The ID of the game
  - player_name: The name of the player

  ## Returns
  A signed token string containing the game_id and player_name
  """
  def generate_token(game_id, player_name) do
    data = %{game_id: game_id, player_name: player_name}
    Phoenix.Token.sign(get_secret_key_base(), @salt, data)
  end

  @doc """
  Validates a token and extracts the game_id and player_name.

  ## Parameters
  - token: The signed token string
  - expected_game_id: The game_id from the URL to validate against

  ## Returns
  {:ok, player_name} if token is valid and game_id matches
  {:error, reason} if token is invalid or game_id doesn't match
  """
  def validate_token(token, expected_game_id) do
    case Phoenix.Token.verify(get_secret_key_base(), @salt, token) do
      {:ok, %{game_id: token_game_id, player_name: player_name}} ->
        if token_game_id == expected_game_id do
          {:ok, player_name}
        else
          {:error, :game_id_mismatch}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Validates a token without game_id verification (for multi-tournament flows).

  ## Parameters
  - token: The signed token string

  ## Returns
  {:ok, {game_id, player_name}} if token is valid
  {:error, reason} if token is invalid
  """
  def decode_token(token) do
    case Phoenix.Token.verify(get_secret_key_base(), @salt, token) do
      {:ok, %{game_id: game_id, player_name: player_name}} ->
        {:ok, {game_id, player_name}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end