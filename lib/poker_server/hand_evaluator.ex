defmodule PokerServer.HandEvaluator do
  @moduledoc """
  Evaluates poker hands using short deck (6+ hold'em) rules.
  
  Key differences from standard poker:
  - Flush beats full house (fewer flush combinations in 36-card deck)  
  - A-6-7-8-9 is the lowest straight (no A-2-3-4-5 wheel)
  - Only cards 6 through Ace are used

  Main functions:
  - evaluate_hand/2: Determine best 5-card hand from 7 available cards
  - determine_winners/1: Compare multiple hands to find winner(s)
  - compare_hands/2: Compare two specific hands
  """

  @doc """
  Get the hand rankings for short deck poker.

  Returns hand types in order from strongest to weakest.
  Note: Flush beats full house in short deck rules.
  """
  @spec hand_rankings() :: [atom()]
  def hand_rankings do
    [
      :straight_flush,
      :four_of_a_kind,
      # Higher than full house in short deck
      :flush,
      :full_house,
      :straight,
      :three_of_a_kind,
      :two_pair,
      :one_pair,
      :high_card
    ]
  end

  @doc """
  Find the winning player(s) from a list of evaluated hands.

  ## Parameters
  - hands: List of {player_id, hand} tuples where hand is {hand_type, cards}

  ## Returns  
  - List of {player_id, hand} tuples for the winning hand(s)
  - Multiple winners in case of ties (split pot scenario)
  - Empty list if no hands provided

  ## Examples
      iex> HandEvaluator.determine_winners([{"player1", {:flush, [cards]}}, {"player2", {:pair, [cards]}}])
      [{"player1", {:flush, [cards]}}]
  """
  @spec determine_winners([{String.t(), {atom(), list()}}]) :: [{String.t(), {atom(), list()}}]
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
      # Lower index = higher rank
      rank1 < rank2 -> :greater
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

    case compare_values(val1, val2) do
      :equal ->
        # Same pair rank - compare kickers
        kickers1 = get_kickers_for_pair(cards1, pair_rank1)
        kickers2 = get_kickers_for_pair(cards2, pair_rank2)
        compare_kickers(kickers1, kickers2)

      result ->
        result
    end
  end

  defp compare_same_hand_type(:two_pair, cards1, cards2) do
    pairs1 = get_two_pair_ranks(cards1)
    pairs2 = get_two_pair_ranks(cards2)

    case compare_two_pair_ranks(pairs1, pairs2) do
      :equal ->
        # Same two pair ranks - compare kicker
        kicker1 = get_kickers_for_two_pair(cards1, pairs1)
        kicker2 = get_kickers_for_two_pair(cards2, pairs2)
        compare_kickers(kicker1, kicker2)

      result ->
        result
    end
  end

  defp compare_same_hand_type(:three_of_a_kind, cards1, cards2) do
    trips_rank1 = find_trips_rank(cards1)
    trips_rank2 = find_trips_rank(cards2)

    val1 = card_rank_value(%{rank: trips_rank1})
    val2 = card_rank_value(%{rank: trips_rank2})

    case compare_values(val1, val2) do
      :equal ->
        # Same trips rank - compare kickers
        kickers1 = get_kickers_for_trips(cards1, trips_rank1)
        kickers2 = get_kickers_for_trips(cards2, trips_rank2)
        compare_kickers(kickers1, kickers2)

      result ->
        result
    end
  end

  defp compare_same_hand_type(:full_house, cards1, cards2) do
    {trips_rank1, pair_rank1} = get_full_house_ranks(cards1)
    {trips_rank2, pair_rank2} = get_full_house_ranks(cards2)

    trips_val1 = card_rank_value(%{rank: trips_rank1})
    trips_val2 = card_rank_value(%{rank: trips_rank2})

    case compare_values(trips_val1, trips_val2) do
      :equal ->
        # Same trips rank - compare pair rank
        pair_val1 = card_rank_value(%{rank: pair_rank1})
        pair_val2 = card_rank_value(%{rank: pair_rank2})
        compare_values(pair_val1, pair_val2)

      result ->
        result
    end
  end

  defp compare_same_hand_type(:high_card, cards1, cards2) do
    # Compare all cards in descending order
    sorted1 = cards1 |> Enum.sort_by(&card_rank_value/1, :desc)
    sorted2 = cards2 |> Enum.sort_by(&card_rank_value/1, :desc)
    compare_kickers(sorted1, sorted2)
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
    sorted_ranks =
      cards
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
      # Not a straight
      _ -> 0
    end
  end

  defp find_pair_rank(cards) do
    cards
    |> Enum.group_by(& &1.rank)
    |> Enum.find(fn {_rank, group} -> length(group) == 2 end)
    |> elem(0)
  end

  # Helper functions for kicker comparisons

  defp compare_values(val1, val2) do
    cond do
      val1 > val2 -> :greater
      val1 < val2 -> :less
      true -> :equal
    end
  end

  defp compare_kickers([], []), do: :equal

  defp compare_kickers([card1 | rest1], [card2 | rest2]) do
    val1 = card_rank_value(card1)
    val2 = card_rank_value(card2)

    case compare_values(val1, val2) do
      :equal -> compare_kickers(rest1, rest2)
      result -> result
    end
  end

  defp get_kickers_for_pair(cards, pair_rank) do
    cards
    |> Enum.reject(&(&1.rank == pair_rank))
    |> Enum.sort_by(&card_rank_value/1, :desc)
  end

  defp get_two_pair_ranks(cards) do
    cards
    |> Enum.group_by(& &1.rank)
    |> Enum.filter(fn {_rank, group} -> length(group) == 2 end)
    |> Enum.map(fn {rank, _group} -> rank end)
    |> Enum.sort_by(&card_rank_value(%{rank: &1}), :desc)
  end

  defp compare_two_pair_ranks([high1, low1], [high2, low2]) do
    high_val1 = card_rank_value(%{rank: high1})
    high_val2 = card_rank_value(%{rank: high2})

    case compare_values(high_val1, high_val2) do
      :equal ->
        low_val1 = card_rank_value(%{rank: low1})
        low_val2 = card_rank_value(%{rank: low2})
        compare_values(low_val1, low_val2)

      result ->
        result
    end
  end

  defp get_kickers_for_two_pair(cards, [high_pair, low_pair]) do
    cards
    |> Enum.reject(&(&1.rank == high_pair || &1.rank == low_pair))
    |> Enum.sort_by(&card_rank_value/1, :desc)
  end

  defp find_trips_rank(cards) do
    cards
    |> Enum.group_by(& &1.rank)
    |> Enum.find(fn {_rank, group} -> length(group) == 3 end)
    |> elem(0)
  end

  defp get_kickers_for_trips(cards, trips_rank) do
    cards
    |> Enum.reject(&(&1.rank == trips_rank))
    |> Enum.sort_by(&card_rank_value/1, :desc)
  end

  defp get_full_house_ranks(cards) do
    rank_counts =
      cards
      |> Enum.group_by(& &1.rank)
      |> Enum.map(fn {rank, group} -> {rank, length(group)} end)

    trips_rank =
      rank_counts
      |> Enum.find(fn {_rank, count} -> count == 3 end)
      |> elem(0)

    pair_rank =
      rank_counts
      |> Enum.find(fn {_rank, count} -> count == 2 end)
      |> elem(0)

    {trips_rank, pair_rank}
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

  @doc """
  Evaluate the best possible poker hand from available cards.

  Takes a player's 2 hole cards plus up to 5 community cards and finds
  the best 5-card poker hand using short deck rules.

  ## Parameters
  - hole_cards: List of 2 Card structs (player's private cards)
  - community_cards: List of 0-5 Card structs (shared board cards)

  ## Returns
  Tuple of {hand_type, cards} where:
  - hand_type: Atom like :flush, :straight, :pair, etc.
  - cards: List of 5 Card structs representing the best hand

  ## Examples
      iex> HandEvaluator.evaluate_hand([card1, card2], [flop1, flop2, flop3])  
      {:pair, [ace_hearts, ace_spades, king_hearts, queen_hearts, jack_hearts]}

  ## Notes
  Uses combinatorics to check all possible 5-card combinations when 7+ cards available.
  Returns the highest-ranking hand according to short deck poker rules.
  """
  @spec evaluate_hand([PokerServer.Card.t()], [PokerServer.Card.t()]) :: {atom(), [PokerServer.Card.t()]}
  def evaluate_hand(hole_cards, community_cards) do
    all_cards = hole_cards ++ community_cards

    # Check all possible 5-card combinations for the best hand
    best_hand =
      if length(all_cards) <= 5 do
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
    for(l <- combinations(t, n - 1), do: [h | l]) ++ combinations(t, n)
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
    rank_counts =
      cards
      |> Enum.group_by(& &1.rank)
      |> Map.values()
      |> Enum.map(&length/1)
      |> Enum.sort(:desc)

    rank_counts == [3, 2] || rank_counts == [3, 2, 1, 1] || rank_counts == [3, 3]
  end

  defp is_straight?(cards) do
    sorted_ranks =
      cards
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
    pair_count =
      cards
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
