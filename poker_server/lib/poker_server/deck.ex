defmodule PokerServer.Deck do
  alias PokerServer.Card

  def create do
    # Use strings that sort correctly alphabetically
    ranks = ["ace", "king", "queen", "jack", "ten", "nine", "eight", "seven", "six"]
    suits = [:clubs, :diamonds, :hearts, :spades]
    
    for rank <- ranks, suit <- suits do
      %Card{rank: String.to_atom(rank), suit: suit}
    end
  end
end