defmodule PokerServer.Deck do
  alias PokerServer.Card

  def create do
    ranks = [:ace, :king, :queen, :jack, :ten, :nine, :eight, :seven, :six]
    suits = [:clubs, :diamonds, :hearts, :spades]
    
    for rank <- ranks, suit <- suits do
      %Card{rank: rank, suit: suit}
    end
  end
end