defmodule PokerServer.HandEvaluator do
  def hand_rankings do
    [
      :straight_flush,
      :four_of_a_kind,
      :flush,           # Higher than full house in short deck
      :full_house,
      :straight,
      :three_of_a_kind,
      :two_pair,
      :one_pair,
      :high_card
    ]
  end

  def determine_winners([]), do: []
end