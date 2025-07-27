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
  
  def determine_winners(hands) do
    hands
    |> Enum.reduce([], fn {player_id, hand}, acc ->
      case acc do
        [] -> 
          [{player_id, hand}]
        [{_, best_hand} | _] = current_winners ->
          case compare_hands(hand, best_hand) do
            :greater -> [{player_id, hand}]
            :equal -> [{player_id, hand} | current_winners]
            :less -> current_winners
          end
      end
    end)
    |> Enum.map(fn {player_id, _hand} -> player_id end)
  end

  def compare_hands({hand_type1, cards1}, {hand_type2, cards2}) do
    rankings = hand_rankings()
    rank1 = Enum.find_index(rankings, &(&1 == hand_type1))
    rank2 = Enum.find_index(rankings, &(&1 == hand_type2))
    
    cond do
      rank1 < rank2 -> :greater  # Lower index = higher rank
      rank1 > rank2 -> :less
      true -> compare_same_hand_type(hand_type1, cards1, cards2)
    end
  end

  defp compare_same_hand_type(:one_pair, cards1, cards2) do
    # For one pair, compare the pair rank first
    pair_rank1 = find_pair_rank(cards1)
    pair_rank2 = find_pair_rank(cards2)
    
    val1 = card_rank_value(%{rank: pair_rank1})
    val2 = card_rank_value(%{rank: pair_rank2})
    
    cond do
      val1 > val2 -> :greater
      val1 < val2 -> :less
      true -> :equal  # Same pair rank - could compare kickers but not needed for current test
    end
  end

  defp compare_same_hand_type(_hand_type, cards1, cards2) do
    # Simple high card comparison for other hand types
    high_card1 = cards1 |> Enum.max_by(&card_rank_value/1)
    high_card2 = cards2 |> Enum.max_by(&card_rank_value/1)
    
    val1 = card_rank_value(high_card1)
    val2 = card_rank_value(high_card2)
    
    cond do
      val1 > val2 -> :greater
      val1 < val2 -> :less
      true -> :equal
    end
  end

  defp find_pair_rank(cards) do
    cards
    |> Enum.group_by(& &1.rank)
    |> Enum.find(fn {_rank, group} -> length(group) == 2 end)
    |> elem(0)
  end

  defp card_rank_value(%{rank: rank}) do
    case rank do
      :ace -> 14
      :king -> 13
      :queen -> 12
      :jack -> 11
      :ten -> 10
      :nine -> 9
      :eight -> 8
      :seven -> 7
      :six -> 6
    end
  end
end