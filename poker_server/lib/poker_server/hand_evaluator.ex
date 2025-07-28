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

  defp compare_same_hand_type(:straight, cards1, cards2) do
    straight_value1 = get_straight_value(cards1)
    straight_value2 = get_straight_value(cards2)
    
    cond do
      straight_value1 > straight_value2 -> :greater
      straight_value1 < straight_value2 -> :less
      true -> :equal
    end
  end

  defp compare_same_hand_type(:straight_flush, cards1, cards2) do
    # Same logic as straight for straight flush
    compare_same_hand_type(:straight, cards1, cards2)
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

  defp get_straight_value(cards) do
    sorted_ranks = cards
    |> Enum.map(&card_rank_value/1)
    |> Enum.uniq()
    |> Enum.sort()
    
    case sorted_ranks do
      # A-6-7-8-9 straight is the lowest (value 1)
      [6, 7, 8, 9, 14] -> 1
      # Regular straights ranked by high card
      [6, 7, 8, 9, 10] -> 10
      [7, 8, 9, 10, 11] -> 11
      [8, 9, 10, 11, 12] -> 12
      [9, 10, 11, 12, 13] -> 13
      [10, 11, 12, 13, 14] -> 14
      _ -> 0  # Not a straight
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

  def evaluate_hand(hole_cards, community_cards) do
    all_cards = hole_cards ++ community_cards
    
    # Check all possible 5-card combinations for the best hand
    best_hand = if length(all_cards) <= 5 do
      evaluate_five_cards(all_cards)
    else
      all_cards
      |> combinations(5)
      |> Enum.map(&evaluate_five_cards/1)
      |> Enum.max_by(fn {hand_type, _cards} -> 
        hand_rankings() |> Enum.find_index(&(&1 == hand_type)) |> then(&(100 - &1))
      end)
    end
    
    best_hand
  end

  defp evaluate_five_cards(cards) do
    cond do
      is_straight_flush?(cards) -> {:straight_flush, cards}
      is_four_of_a_kind?(cards) -> {:four_of_a_kind, cards}
      is_flush?(cards) -> {:flush, cards}
      is_full_house?(cards) -> {:full_house, cards}
      is_straight?(cards) -> {:straight, cards}
      is_three_of_a_kind?(cards) -> {:three_of_a_kind, cards}
      is_two_pair?(cards) -> {:two_pair, cards}
      is_one_pair?(cards) -> {:one_pair, cards}
      true -> {:high_card, cards}
    end
  end

  defp combinations([], _), do: [[]]
  defp combinations(_, 0), do: [[]]
  defp combinations([h | t], n) when n > 0 do
    (for(l <- combinations(t, n - 1), do: [h | l])) ++ combinations(t, n)
  end

  defp is_straight_flush?(cards) do
    is_flush?(cards) && is_straight?(cards)
  end

  defp is_four_of_a_kind?(cards) do
    cards
    |> Enum.group_by(& &1.rank)
    |> Map.values()
    |> Enum.any?(&(length(&1) == 4))
  end

  defp is_flush?(cards) do
    cards
    |> Enum.group_by(& &1.suit)
    |> Map.values()
    |> Enum.any?(&(length(&1) >= 5))
  end

  defp is_full_house?(cards) do
    rank_counts = cards
    |> Enum.group_by(& &1.rank)
    |> Map.values()
    |> Enum.map(&length/1)
    |> Enum.sort(:desc)
    
    rank_counts == [3, 2] || rank_counts == [3, 2, 1, 1] || rank_counts == [3, 3]
  end

  defp is_straight?(cards) do
    sorted_ranks = cards
    |> Enum.map(&card_rank_value/1)
    |> Enum.uniq()
    |> Enum.sort()
    
    case sorted_ranks do
      # Regular straights in short deck
      [6, 7, 8, 9, 10] -> true
      [7, 8, 9, 10, 11] -> true
      [8, 9, 10, 11, 12] -> true
      [9, 10, 11, 12, 13] -> true
      [10, 11, 12, 13, 14] -> true
      # A-6-7-8-9 straight (lowest possible straight in short deck)
      [6, 7, 8, 9, 14] -> true
      _ -> false
    end
  end

  defp is_three_of_a_kind?(cards) do
    cards
    |> Enum.group_by(& &1.rank)
    |> Map.values()
    |> Enum.any?(&(length(&1) == 3))
  end

  defp is_two_pair?(cards) do
    pair_count = cards
    |> Enum.group_by(& &1.rank)
    |> Map.values()
    |> Enum.count(&(length(&1) == 2))
    
    pair_count >= 2
  end

  defp is_one_pair?(cards) do
    cards
    |> Enum.group_by(& &1.rank)
    |> Map.values()
    |> Enum.any?(&(length(&1) == 2))
  end
end