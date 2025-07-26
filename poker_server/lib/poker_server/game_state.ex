defmodule PokerServer.GameState do
  alias PokerServer.Deck
  
  defstruct [:players, :community_cards, :pot, :phase, :hand_number, :deck, :button_position, :small_blind, :big_blind]

  def new(players) do
    %__MODULE__{
      players: players,
      phase: :waiting_for_players,
      hand_number: 0,
      pot: 0,
      community_cards: [],
      button_position: Enum.random(0..5),
      deck: Deck.create()
    }
  end
end