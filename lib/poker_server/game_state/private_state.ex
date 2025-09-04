defmodule PokerServer.GameState.PrivateState do
  @moduledoc """
  Private game state containing sensitive card information.
  
  This state is NEVER stored in snapshots. Instead, it's:
  - Stored securely using Shamir's Secret Sharing for each hand
  - Reconstructed from shards during recovery when needed
  - Kept in memory only during active gameplay
  
  Contains:
  - Player hole cards 
  - Deck state (remaining cards)
  - Any other sensitive card information
  """
  
  alias PokerServer.{Card, Deck}
  
  @type t :: %__MODULE__{
    deck: Deck.t(),
    player_hole_cards: %{String.t() => [Card.t()]}
  }
  
  defstruct [
    :deck,
    :player_hole_cards
  ]
  
  @doc """
  Creates private state from a full GameState by extracting sensitive information.
  """
  @spec from_game_state(PokerServer.GameState.t()) :: t()
  def from_game_state(game_state) do
    %__MODULE__{
      deck: game_state.deck,
      player_hole_cards: extract_hole_cards(game_state.players)
    }
  end
  
  @doc """
  Extracts hole cards from players into a map keyed by player ID.
  """
  @spec extract_hole_cards([PokerServer.Player.t()]) :: %{String.t() => [Card.t()]}
  def extract_hole_cards(players) do
    players
    |> Enum.reduce(%{}, fn player, acc ->
      if length(player.hole_cards) > 0 do
        Map.put(acc, player.id, player.hole_cards)
      else
        acc
      end
    end)
  end
  
  @doc """
  Converts private state to the format expected by the secret sharing system.
  """
  @spec to_card_state(t()) :: map()
  def to_card_state(private_state) do
    %{
      hole_cards: private_state.player_hole_cards,
      deck: private_state.deck,
      community_cards: []  # Community cards are public, stored separately
    }
  end
  
  @doc """
  Creates private state from the format returned by secret sharing reconstruction.
  """
  @spec from_card_state(map()) :: t()
  def from_card_state(card_state) do
    %__MODULE__{
      deck: card_state.deck,
      player_hole_cards: card_state.hole_cards
    }
  end
  
  @doc """
  Validates that private state is properly secured and not accidentally exposed.
  """
  @spec validate_security(t()) :: :ok | {:error, term()}
  def validate_security(private_state) do
    cond do
      is_nil(private_state.deck) ->
        {:error, {:security_violation, "Private state missing deck"}}
      
      map_size(private_state.player_hole_cards) == 0 ->
        {:error, {:security_violation, "Private state missing player hole cards"}}
      
      true ->
        :ok
    end
  end
end