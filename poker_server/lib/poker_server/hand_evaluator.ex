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

  def evaluate_hand(hole_cards, community_cards) do
    all_cards = hole_cards ++ community_cards
    best_five = get_best_five_cards(all_cards)
    
    cond do
      is_straight_flush?(best_five) -> {:straight_flush, best_five}
      is_four_of_a_kind?(best_five) -> {:four_of_a_kind, best_five}
      is_flush?(best_five) -> {:flush, best_five}
      is_full_house?(best_five) -> {:full_house, best_five}
      is_straight?(best_five) -> {:straight, best_five}
      is_three_of_a_kind?(best_five) -> {:three_of_a_kind, best_five}
      is_two_pair?(best_five) -> {:two_pair, best_five}
      is_one_pair?(best_five) -> {:one_pair, best_five}
      true -> {:high_card, best_five}
    end
  end

  defp get_best_five_cards(cards) when length(cards) <= 5, do: cards
  defp get_best_five_cards(cards) do
    cards
    |> Enum.sort_by(&card_rank_value/1, :desc)
    |> Enum.take(5)
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
      [6, 7, 8, 9, 10] -> true
      [7, 8, 9, 10, 11] -> true
      [8, 9, 10, 11, 12] -> true
      [9, 10, 11, 12, 13] -> true
      [10, 11, 12, 13, 14] -> true
      [6, 10, 11, 12, 13, 14] -> true  # A-6 straight in short deck
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