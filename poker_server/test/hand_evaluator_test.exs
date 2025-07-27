defmodule PokerServer.HandEvaluatorTest do
  use ExUnit.Case
  alias PokerServer.{HandEvaluator, Card}

  # Helper to create cards easily
  defp card(rank, suit), do: %Card{rank: rank, suit: suit}

  describe "evaluate_hand/2" do
    test "identifies straight flush" do
      hole_cards = [card(:ace, :hearts), card(:king, :hearts)]
      community = [card(:queen, :hearts), card(:jack, :hearts), card(:ten, :hearts), card(:nine, :spades), card(:eight, :clubs)]
      
      {hand_type, _cards} = HandEvaluator.evaluate_hand(hole_cards, community)
      assert hand_type == :straight_flush
    end

    test "identifies four of a kind" do
      hole_cards = [card(:ace, :hearts), card(:ace, :diamonds)]
      community = [card(:ace, :clubs), card(:ace, :spades), card(:king, :hearts), card(:queen, :spades), card(:jack, :clubs)]
      
      {hand_type, _cards} = HandEvaluator.evaluate_hand(hole_cards, community)
      assert hand_type == :four_of_a_kind
    end

    test "identifies full house" do
      hole_cards = [card(:ace, :hearts), card(:ace, :diamonds)]
      community = [card(:ace, :clubs), card(:king, :spades), card(:king, :hearts), card(:queen, :spades), card(:jack, :clubs)]
      
      {hand_type, _cards} = HandEvaluator.evaluate_hand(hole_cards, community)
      assert hand_type == :full_house
    end

    test "identifies flush" do
      hole_cards = [card(:ace, :hearts), card(:king, :hearts)]
      community = [card(:queen, :hearts), card(:jack, :hearts), card(:nine, :hearts), card(:eight, :spades), card(:seven, :clubs)]
      
      {hand_type, _cards} = HandEvaluator.evaluate_hand(hole_cards, community)
      assert hand_type == :flush
    end

    test "identifies straight" do
      hole_cards = [card(:ace, :hearts), card(:king, :diamonds)]
      community = [card(:queen, :hearts), card(:jack, :spades), card(:ten, :clubs), card(:nine, :hearts), card(:eight, :clubs)]
      
      {hand_type, _cards} = HandEvaluator.evaluate_hand(hole_cards, community)
      assert hand_type == :straight
    end

    test "identifies three of a kind" do
      hole_cards = [card(:ace, :hearts), card(:ace, :diamonds)]
      community = [card(:ace, :clubs), card(:king, :spades), card(:queen, :hearts), card(:jack, :spades), card(:ten, :clubs)]
      
      {hand_type, _cards} = HandEvaluator.evaluate_hand(hole_cards, community)
      assert hand_type == :three_of_a_kind
    end

    test "identifies two pair" do
      hole_cards = [card(:ace, :hearts), card(:ace, :diamonds)]
      community = [card(:king, :clubs), card(:king, :spades), card(:queen, :hearts), card(:jack, :spades), card(:ten, :clubs)]
      
      {hand_type, _cards} = HandEvaluator.evaluate_hand(hole_cards, community)
      assert hand_type == :two_pair
    end

    test "identifies one pair" do
      hole_cards = [card(:ace, :hearts), card(:ace, :diamonds)]
      community = [card(:king, :clubs), card(:queen, :spades), card(:jack, :hearts), card(:ten, :spades), card(:nine, :clubs)]
      
      {hand_type, _cards} = HandEvaluator.evaluate_hand(hole_cards, community)
      assert hand_type == :one_pair
    end

    test "identifies high card" do
      hole_cards = [card(:ace, :hearts), card(:king, :diamonds)]
      community = [card(:queen, :clubs), card(:jack, :spades), card(:nine, :hearts), card(:eight, :spades), card(:six, :clubs)]
      
      {hand_type, _cards} = HandEvaluator.evaluate_hand(hole_cards, community)
      assert hand_type == :high_card
    end

    test "uses best 5 cards from 7 available" do
      hole_cards = [card(:ace, :hearts), card(:six, :diamonds)]
      community = [card(:king, :clubs), card(:queen, :spades), card(:jack, :hearts), card(:ten, :spades), card(:nine, :clubs)]
      
      {hand_type, best_cards} = HandEvaluator.evaluate_hand(hole_cards, community)
      assert hand_type == :straight
      assert length(best_cards) == 5
      
      ranks = best_cards |> Enum.map(& &1.rank) |> Enum.sort()
      expected_ranks = [:ace, :king, :queen, :jack, :ten] |> Enum.sort()
      assert ranks == expected_ranks
    end
  end

  describe "compare_hands/2" do
    test "straight flush beats four of a kind" do
      sf_hand = {:straight_flush, [card(:ace, :hearts), card(:king, :hearts), card(:queen, :hearts), card(:jack, :hearts), card(:ten, :hearts)]}
      foak_hand = {:four_of_a_kind, [card(:ace, :clubs), card(:ace, :diamonds), card(:ace, :hearts), card(:ace, :spades), card(:king, :clubs)]}
      
      assert HandEvaluator.compare_hands(sf_hand, foak_hand) == :greater
      assert HandEvaluator.compare_hands(foak_hand, sf_hand) == :less
    end

    test "four of a kind beats full house" do
      foak_hand = {:four_of_a_kind, [card(:king, :clubs), card(:king, :diamonds), card(:king, :hearts), card(:king, :spades), card(:ace, :clubs)]}
      fh_hand = {:full_house, [card(:ace, :clubs), card(:ace, :diamonds), card(:ace, :hearts), card(:queen, :spades), card(:queen, :clubs)]}
      
      assert HandEvaluator.compare_hands(foak_hand, fh_hand) == :greater
    end

    test "flush beats full house in short deck" do
      flush_hand = {:flush, [card(:ace, :hearts), card(:king, :hearts), card(:queen, :hearts), card(:jack, :hearts), card(:nine, :hearts)]}
      fh_hand = {:full_house, [card(:ace, :clubs), card(:ace, :diamonds), card(:ace, :hearts), card(:king, :spades), card(:king, :clubs)]}
      
      assert HandEvaluator.compare_hands(flush_hand, fh_hand) == :greater
    end

    test "full house beats straight" do
      fh_hand = {:full_house, [card(:ace, :clubs), card(:ace, :diamonds), card(:ace, :hearts), card(:king, :spades), card(:king, :clubs)]}
      straight_hand = {:straight, [card(:ace, :hearts), card(:king, :diamonds), card(:queen, :clubs), card(:jack, :spades), card(:ten, :hearts)]}
      
      assert HandEvaluator.compare_hands(fh_hand, straight_hand) == :greater
    end

    test "compares same hand types by high card" do
      high_pair = {:one_pair, [card(:ace, :hearts), card(:ace, :diamonds), card(:king, :clubs), card(:queen, :spades), card(:jack, :hearts)]}
      low_pair = {:one_pair, [card(:king, :hearts), card(:king, :diamonds), card(:ace, :clubs), card(:queen, :spades), card(:jack, :hearts)]}
      
      assert HandEvaluator.compare_hands(high_pair, low_pair) == :greater
    end

    test "returns equal for identical hands" do
      hand1 = {:one_pair, [card(:ace, :hearts), card(:ace, :diamonds), card(:king, :clubs), card(:queen, :spades), card(:jack, :hearts)]}
      hand2 = {:one_pair, [card(:ace, :clubs), card(:ace, :spades), card(:king, :hearts), card(:queen, :diamonds), card(:jack, :clubs)]}
      
      assert HandEvaluator.compare_hands(hand1, hand2) == :equal
    end
  end

  describe "determine_winners/1" do
    test "returns single winner" do
      hands = [
        {1, {:one_pair, [card(:ace, :hearts), card(:ace, :diamonds), card(:king, :clubs), card(:queen, :spades), card(:jack, :hearts)]}},
        {2, {:high_card, [card(:king, :hearts), card(:queen, :diamonds), card(:jack, :clubs), card(:ten, :spades), card(:nine, :hearts)]}}
      ]
      
      winners = HandEvaluator.determine_winners(hands)
      assert winners == [1]
    end

    test "returns multiple winners for tie" do
      hands = [
        {1, {:one_pair, [card(:ace, :hearts), card(:ace, :diamonds), card(:king, :clubs), card(:queen, :spades), card(:jack, :hearts)]}},
        {2, {:one_pair, [card(:ace, :clubs), card(:ace, :spades), card(:king, :hearts), card(:queen, :diamonds), card(:jack, :clubs)]}},
        {3, {:high_card, [card(:king, :hearts), card(:queen, :diamonds), card(:jack, :clubs), card(:ten, :spades), card(:nine, :hearts)]}}
      ]
      
      winners = HandEvaluator.determine_winners(hands)
      assert Enum.sort(winners) == [1, 2]
    end

    test "handles empty hands list" do
      assert HandEvaluator.determine_winners([]) == []
    end
  end

  describe "hand ranking order" do
    test "validates short deck hand ranking order" do
      # In short deck, flush beats full house
      hand_rankings = [
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
      
      assert HandEvaluator.hand_rankings() == hand_rankings
    end
  end
end