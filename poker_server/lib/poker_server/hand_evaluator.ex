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

  def compare_hands({hand_type1, _cards1}, {hand_type2, _cards2}) do
    rankings = hand_rankings()
    rank1 = Enum.find_index(rankings, &(&1 == hand_type1))
    rank2 = Enum.find_index(rankings, &(&1 == hand_type2))
    
    cond do
      rank1 < rank2 -> :greater  # Lower index = higher rank
      rank1 > rank2 -> :less
      true -> :equal
    end
  end
end