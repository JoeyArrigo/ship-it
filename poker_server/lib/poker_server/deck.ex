defmodule PokerServer.Deck do
  alias PokerServer.Card
  
  @type t :: [Card.t()]

  def create do
    # Use strings that sort correctly alphabetically
    ranks = ["ace", "king", "queen", "jack", "ten", "nine", "eight", "seven", "six"]
    suits = [:clubs, :diamonds, :hearts, :spades]
    
    for rank <- ranks, suit <- suits do
      %Card{rank: String.to_atom(rank), suit: suit}
    end
  end

  def shuffle(deck) do
    Enum.shuffle(deck)
  end

  def deal_card([card | remaining_deck]) do
    {card, remaining_deck}
  end
  
  def deal_card([]) do
    raise ArgumentError, "cannot deal from empty deck"
  end

  def deal_cards(deck, count) when count > length(deck) do
    raise ArgumentError, "not enough cards in deck"
  end
  
  def deal_cards(deck, count) do
    {Enum.take(deck, count), Enum.drop(deck, count)}
  end

  def cards_remaining(deck) do
    length(deck)
  end
end