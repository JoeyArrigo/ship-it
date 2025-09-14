defmodule PokerServer.Player.PublicPlayer do
  @moduledoc """
  Public player information that can be safely shared in snapshots.
  
  Contains all player data except for their private hole cards.
  """
  
  @derive Jason.Encoder
  @type t :: %__MODULE__{
    id: String.t(),
    chips: non_neg_integer(),
    position: non_neg_integer() | nil,
    hole_cards: []  # Always empty for security
  }
  
  defstruct [:id, :chips, :position, hole_cards: []]
  
  @doc """
  Creates a public player from a full Player struct by removing hole cards.
  """
  @spec from_player(PokerServer.Player.t()) :: t()
  def from_player(player) do
    %__MODULE__{
      id: player.id,
      chips: player.chips,
      position: player.position,
      hole_cards: []  # Always strip hole cards for security
    }
  end
  
  @doc """
  Creates a full Player struct by merging public data with hole cards from private state.
  """
  @spec to_player(t(), [PokerServer.Card.t()]) :: PokerServer.Player.t()
  def to_player(public_player, hole_cards \\ []) do
    %PokerServer.Player{
      id: public_player.id,
      chips: public_player.chips,
      position: public_player.position,
      hole_cards: hole_cards
    }
  end
end