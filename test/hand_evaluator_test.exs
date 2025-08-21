defmodule PokerServer.HandEvaluatorTest do
  use ExUnit.Case
  alias PokerServer.{HandEvaluator, Card}

  # Helper to create cards easily
  defp card(rank, suit), do: %Card{rank: rank, suit: suit}

  describe "evaluate_hand/2" do
    test "identifies straight flush" do
      hole_cards = [card(:ace, :hearts), card(:king, :hearts)]

      community = [
        card(:queen, :hearts),
        card(:jack, :hearts),
        card(:ten, :hearts),
        card(:nine, :spades),
        card(:eight, :clubs)
      ]

      {hand_type, _cards} = HandEvaluator.evaluate_hand(hole_cards, community)
      assert hand_type == :straight_flush
    end

    test "identifies four of a kind" do
      hole_cards = [card(:ace, :hearts), card(:ace, :diamonds)]

      community = [
        card(:ace, :clubs),
        card(:ace, :spades),
        card(:king, :hearts),
        card(:queen, :spades),
        card(:jack, :clubs)
      ]

      {hand_type, _cards} = HandEvaluator.evaluate_hand(hole_cards, community)
      assert hand_type == :four_of_a_kind
    end

    test "identifies full house" do
      hole_cards = [card(:ace, :hearts), card(:ace, :diamonds)]

      community = [
        card(:ace, :clubs),
        card(:king, :spades),
        card(:king, :hearts),
        card(:queen, :spades),
        card(:jack, :clubs)
      ]

      {hand_type, _cards} = HandEvaluator.evaluate_hand(hole_cards, community)
      assert hand_type == :full_house
    end

    test "identifies flush" do
      hole_cards = [card(:ace, :hearts), card(:king, :hearts)]

      community = [
        card(:queen, :hearts),
        card(:jack, :hearts),
        card(:nine, :hearts),
        card(:eight, :spades),
        card(:seven, :clubs)
      ]

      {hand_type, _cards} = HandEvaluator.evaluate_hand(hole_cards, community)
      assert hand_type == :flush
    end

    test "identifies straight" do
      hole_cards = [card(:ace, :hearts), card(:king, :diamonds)]

      community = [
        card(:queen, :hearts),
        card(:jack, :spades),
        card(:ten, :clubs),
        card(:nine, :hearts),
        card(:eight, :clubs)
      ]

      {hand_type, _cards} = HandEvaluator.evaluate_hand(hole_cards, community)
      assert hand_type == :straight
    end

    test "identifies three of a kind" do
      hole_cards = [card(:ace, :hearts), card(:ace, :diamonds)]

      community = [
        card(:ace, :clubs),
        card(:king, :spades),
        card(:queen, :hearts),
        card(:nine, :spades),
        card(:eight, :clubs)
      ]

      {hand_type, _cards} = HandEvaluator.evaluate_hand(hole_cards, community)
      assert hand_type == :three_of_a_kind
    end

    test "identifies two pair" do
      hole_cards = [card(:ace, :hearts), card(:ace, :diamonds)]

      community = [
        card(:king, :clubs),
        card(:king, :spades),
        card(:queen, :hearts),
        card(:nine, :spades),
        card(:eight, :clubs)
      ]

      {hand_type, _cards} = HandEvaluator.evaluate_hand(hole_cards, community)
      assert hand_type == :two_pair
    end

    test "identifies one pair" do
      hole_cards = [card(:ace, :hearts), card(:ace, :diamonds)]

      community = [
        card(:king, :clubs),
        card(:queen, :spades),
        card(:jack, :hearts),
        card(:eight, :spades),
        card(:six, :clubs)
      ]

      {hand_type, _cards} = HandEvaluator.evaluate_hand(hole_cards, community)
      assert hand_type == :one_pair
    end

    test "identifies high card" do
      hole_cards = [card(:ace, :hearts), card(:king, :diamonds)]

      community = [
        card(:queen, :clubs),
        card(:jack, :spades),
        card(:nine, :hearts),
        card(:eight, :spades),
        card(:six, :clubs)
      ]

      {hand_type, _cards} = HandEvaluator.evaluate_hand(hole_cards, community)
      assert hand_type == :high_card
    end

    test "uses best 5 cards from 7 available" do
      hole_cards = [card(:ace, :hearts), card(:six, :diamonds)]

      community = [
        card(:king, :clubs),
        card(:queen, :spades),
        card(:jack, :hearts),
        card(:ten, :spades),
        card(:nine, :clubs)
      ]

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
      sf_hand =
        {:straight_flush,
         [
           card(:ace, :hearts),
           card(:king, :hearts),
           card(:queen, :hearts),
           card(:jack, :hearts),
           card(:ten, :hearts)
         ]}

      foak_hand =
        {:four_of_a_kind,
         [
           card(:ace, :clubs),
           card(:ace, :diamonds),
           card(:ace, :hearts),
           card(:ace, :spades),
           card(:king, :clubs)
         ]}

      assert HandEvaluator.compare_hands(sf_hand, foak_hand) == :greater
      assert HandEvaluator.compare_hands(foak_hand, sf_hand) == :less
    end

    test "four of a kind beats full house" do
      foak_hand =
        {:four_of_a_kind,
         [
           card(:king, :clubs),
           card(:king, :diamonds),
           card(:king, :hearts),
           card(:king, :spades),
           card(:ace, :clubs)
         ]}

      fh_hand =
        {:full_house,
         [
           card(:ace, :clubs),
           card(:ace, :diamonds),
           card(:ace, :hearts),
           card(:queen, :spades),
           card(:queen, :clubs)
         ]}

      assert HandEvaluator.compare_hands(foak_hand, fh_hand) == :greater
    end

    test "flush beats full house in short deck" do
      flush_hand =
        {:flush,
         [
           card(:ace, :hearts),
           card(:king, :hearts),
           card(:queen, :hearts),
           card(:jack, :hearts),
           card(:nine, :hearts)
         ]}

      fh_hand =
        {:full_house,
         [
           card(:ace, :clubs),
           card(:ace, :diamonds),
           card(:ace, :hearts),
           card(:king, :spades),
           card(:king, :clubs)
         ]}

      assert HandEvaluator.compare_hands(flush_hand, fh_hand) == :greater
    end

    test "full house beats straight" do
      fh_hand =
        {:full_house,
         [
           card(:ace, :clubs),
           card(:ace, :diamonds),
           card(:ace, :hearts),
           card(:king, :spades),
           card(:king, :clubs)
         ]}

      straight_hand =
        {:straight,
         [
           card(:ace, :hearts),
           card(:king, :diamonds),
           card(:queen, :clubs),
           card(:jack, :spades),
           card(:ten, :hearts)
         ]}

      assert HandEvaluator.compare_hands(fh_hand, straight_hand) == :greater
    end

    test "compares same hand types by high card" do
      high_pair =
        {:one_pair,
         [
           card(:ace, :hearts),
           card(:ace, :diamonds),
           card(:king, :clubs),
           card(:queen, :spades),
           card(:jack, :hearts)
         ]}

      low_pair =
        {:one_pair,
         [
           card(:king, :hearts),
           card(:king, :diamonds),
           card(:ace, :clubs),
           card(:queen, :spades),
           card(:jack, :hearts)
         ]}

      assert HandEvaluator.compare_hands(high_pair, low_pair) == :greater
    end

    test "returns equal for identical hands" do
      hand1 =
        {:one_pair,
         [
           card(:ace, :hearts),
           card(:ace, :diamonds),
           card(:king, :clubs),
           card(:queen, :spades),
           card(:jack, :hearts)
         ]}

      hand2 =
        {:one_pair,
         [
           card(:ace, :clubs),
           card(:ace, :spades),
           card(:king, :hearts),
           card(:queen, :diamonds),
           card(:jack, :clubs)
         ]}

      assert HandEvaluator.compare_hands(hand1, hand2) == :equal
    end
  end

  describe "determine_winners/1" do
    test "returns single winner" do
      hands = [
        {1,
         {:one_pair,
          [
            card(:ace, :hearts),
            card(:ace, :diamonds),
            card(:king, :clubs),
            card(:queen, :spades),
            card(:jack, :hearts)
          ]}},
        {2,
         {:high_card,
          [
            card(:king, :hearts),
            card(:queen, :diamonds),
            card(:jack, :clubs),
            card(:ten, :spades),
            card(:nine, :hearts)
          ]}}
      ]

      winners = HandEvaluator.determine_winners(hands)
      assert winners == [1]
    end

    test "returns multiple winners for tie" do
      hands = [
        {1,
         {:one_pair,
          [
            card(:ace, :hearts),
            card(:ace, :diamonds),
            card(:king, :clubs),
            card(:queen, :spades),
            card(:jack, :hearts)
          ]}},
        {2,
         {:one_pair,
          [
            card(:ace, :clubs),
            card(:ace, :spades),
            card(:king, :hearts),
            card(:queen, :diamonds),
            card(:jack, :clubs)
          ]}},
        {3,
         {:high_card,
          [
            card(:king, :hearts),
            card(:queen, :diamonds),
            card(:jack, :clubs),
            card(:ten, :spades),
            card(:nine, :hearts)
          ]}}
      ]

      winners = HandEvaluator.determine_winners(hands)
      assert Enum.sort(winners) == [1, 2]
    end

    test "determines winner by kickers" do
      hands = [
        {1,
         {:one_pair,
          [
            card(:ace, :hearts),
            card(:ace, :diamonds),
            card(:king, :clubs),
            card(:queen, :spades),
            card(:jack, :hearts)
          ]}},
        {2,
         {:one_pair,
          [
            card(:ace, :clubs),
            card(:ace, :spades),
            card(:king, :hearts),
            card(:queen, :diamonds),
            card(:ten, :clubs)
          ]}},
        {3,
         {:one_pair,
          [
            card(:ace, :hearts),
            card(:ace, :clubs),
            card(:king, :spades),
            card(:queen, :hearts),
            card(:nine, :diamonds)
          ]}}
      ]

      # All have AA-KQ, but different final kickers: J vs 10 vs 9
      winners = HandEvaluator.determine_winners(hands)
      # Player 1 wins with Jack kicker
      assert winners == [1]
    end

    test "determines winner with two pair kickers" do
      hands = [
        {1,
         {:two_pair,
          [
            card(:ace, :hearts),
            card(:ace, :diamonds),
            card(:king, :clubs),
            card(:king, :spades),
            card(:queen, :hearts)
          ]}},
        {2,
         {:two_pair,
          [
            card(:ace, :clubs),
            card(:ace, :spades),
            card(:king, :hearts),
            card(:king, :diamonds),
            card(:jack, :clubs)
          ]}},
        {3,
         {:two_pair,
          [
            card(:ace, :hearts),
            card(:ace, :clubs),
            card(:king, :spades),
            card(:king, :hearts),
            card(:ten, :diamonds)
          ]}}
      ]

      # All have AA-KK, but different kickers: Q vs J vs 10
      winners = HandEvaluator.determine_winners(hands)
      # Player 1 wins with Queen kicker
      assert winners == [1]
    end

    test "handles empty hands list" do
      assert HandEvaluator.determine_winners([]) == []
    end
  end

  describe "short deck straight edge cases" do
    test "identifies A-6-7-8-9 straight (lowest possible in short deck)" do
      hole_cards = [card(:ace, :hearts), card(:six, :diamonds)]

      community = [
        card(:seven, :clubs),
        card(:eight, :spades),
        card(:nine, :hearts),
        card(:king, :clubs),
        card(:queen, :diamonds)
      ]

      {hand_type, _cards} = HandEvaluator.evaluate_hand(hole_cards, community)
      assert hand_type == :straight
    end

    test "identifies 6-7-8-9-10 straight" do
      hole_cards = [card(:six, :hearts), card(:seven, :diamonds)]

      community = [
        card(:eight, :clubs),
        card(:nine, :spades),
        card(:ten, :hearts),
        card(:king, :clubs),
        card(:queen, :diamonds)
      ]

      {hand_type, _cards} = HandEvaluator.evaluate_hand(hole_cards, community)
      assert hand_type == :straight
    end

    test "identifies 10-J-Q-K-A straight (highest possible in short deck)" do
      hole_cards = [card(:ace, :hearts), card(:ten, :diamonds)]

      community = [
        card(:jack, :clubs),
        card(:queen, :spades),
        card(:king, :hearts),
        card(:nine, :clubs),
        card(:eight, :diamonds)
      ]

      {hand_type, _cards} = HandEvaluator.evaluate_hand(hole_cards, community)
      assert hand_type == :straight
    end

    test "A-6-7-8-9 straight beats no straight" do
      wheel_straight =
        {:straight,
         [
           card(:ace, :hearts),
           card(:six, :diamonds),
           card(:seven, :clubs),
           card(:eight, :spades),
           card(:nine, :hearts)
         ]}

      high_card =
        {:high_card,
         [
           card(:ace, :clubs),
           card(:king, :diamonds),
           card(:queen, :hearts),
           card(:jack, :spades),
           card(:ten, :clubs)
         ]}

      assert HandEvaluator.compare_hands(wheel_straight, high_card) == :greater
    end

    test "6-7-8-9-10 straight beats A-6-7-8-9 straight" do
      regular_straight =
        {:straight,
         [
           card(:six, :hearts),
           card(:seven, :diamonds),
           card(:eight, :clubs),
           card(:nine, :spades),
           card(:ten, :hearts)
         ]}

      wheel_straight =
        {:straight,
         [
           card(:ace, :hearts),
           card(:six, :diamonds),
           card(:seven, :clubs),
           card(:eight, :spades),
           card(:nine, :hearts)
         ]}

      assert HandEvaluator.compare_hands(regular_straight, wheel_straight) == :greater
      assert HandEvaluator.compare_hands(wheel_straight, regular_straight) == :less
    end

    test "10-J-Q-K-A straight beats 6-7-8-9-10 straight" do
      ace_high_straight =
        {:straight,
         [
           card(:ace, :hearts),
           card(:ten, :diamonds),
           card(:jack, :clubs),
           card(:queen, :spades),
           card(:king, :hearts)
         ]}

      six_high_straight =
        {:straight,
         [
           card(:six, :hearts),
           card(:seven, :diamonds),
           card(:eight, :clubs),
           card(:nine, :spades),
           card(:ten, :hearts)
         ]}

      assert HandEvaluator.compare_hands(ace_high_straight, six_high_straight) == :greater
      assert HandEvaluator.compare_hands(six_high_straight, ace_high_straight) == :less
    end

    test "straight flush with A-6-7-8-9 beats four of a kind" do
      wheel_straight_flush =
        {:straight_flush,
         [
           card(:ace, :hearts),
           card(:six, :hearts),
           card(:seven, :hearts),
           card(:eight, :hearts),
           card(:nine, :hearts)
         ]}

      four_kings =
        {:four_of_a_kind,
         [
           card(:king, :clubs),
           card(:king, :diamonds),
           card(:king, :hearts),
           card(:king, :spades),
           card(:ace, :clubs)
         ]}

      assert HandEvaluator.compare_hands(wheel_straight_flush, four_kings) == :greater
    end

    test "higher straight flush beats lower straight flush" do
      ace_high_sf =
        {:straight_flush,
         [
           card(:ace, :hearts),
           card(:ten, :hearts),
           card(:jack, :hearts),
           card(:queen, :hearts),
           card(:king, :hearts)
         ]}

      wheel_sf =
        {:straight_flush,
         [
           card(:ace, :spades),
           card(:six, :spades),
           card(:seven, :spades),
           card(:eight, :spades),
           card(:nine, :spades)
         ]}

      assert HandEvaluator.compare_hands(ace_high_sf, wheel_sf) == :greater
      assert HandEvaluator.compare_hands(wheel_sf, ace_high_sf) == :less
    end

    test "does not identify invalid sequences as straights" do
      # A-7-8-9-10 is not a valid straight (missing 6)
      hole_cards = [card(:ace, :hearts), card(:seven, :diamonds)]

      community = [
        card(:eight, :clubs),
        card(:nine, :spades),
        card(:ten, :hearts),
        card(:king, :clubs),
        card(:queen, :diamonds)
      ]

      {hand_type, _cards} = HandEvaluator.evaluate_hand(hole_cards, community)
      refute hand_type == :straight
    end

    test "does not identify gap sequences as straights" do
      # Cards with no possible 5-card straight: 6, 8, 10, Q, A (all scattered)
      hole_cards = [card(:six, :hearts), card(:eight, :diamonds)]

      community = [
        card(:ten, :clubs),
        card(:queen, :spades),
        card(:ace, :hearts),
        card(:six, :clubs),
        card(:eight, :spades)
      ]

      {hand_type, _cards} = HandEvaluator.evaluate_hand(hole_cards, community)
      # Available cards: 6, 6, 8, 8, 10, Q, A - has two pair, not straight
      assert hand_type == :two_pair
    end
  end

  describe "kicker comparisons" do
    test "one pair with different kickers" do
      # Both have pair of Aces, different kickers
      hand1 =
        {:one_pair,
         [
           card(:ace, :hearts),
           card(:ace, :diamonds),
           card(:king, :clubs),
           card(:queen, :spades),
           card(:jack, :hearts)
         ]}

      hand2 =
        {:one_pair,
         [
           card(:ace, :clubs),
           card(:ace, :spades),
           card(:king, :hearts),
           card(:queen, :diamonds),
           card(:ten, :clubs)
         ]}

      # First hand has J kicker, second has 10 kicker - first should win
      assert HandEvaluator.compare_hands(hand1, hand2) == :greater
      assert HandEvaluator.compare_hands(hand2, hand1) == :less
    end

    test "one pair with multiple kicker comparisons" do
      # Both have pair of Kings, need to compare multiple kickers
      hand1 =
        {:one_pair,
         [
           card(:king, :hearts),
           card(:king, :diamonds),
           card(:ace, :clubs),
           card(:nine, :spades),
           card(:eight, :hearts)
         ]}

      hand2 =
        {:one_pair,
         [
           card(:king, :clubs),
           card(:king, :spades),
           card(:ace, :hearts),
           card(:nine, :diamonds),
           card(:seven, :clubs)
         ]}

      # Same pair (KK), same first kicker (A), same second kicker (9), third kicker differs (8 vs 7)
      assert HandEvaluator.compare_hands(hand1, hand2) == :greater
    end

    test "two pair with different high pairs" do
      hand1 =
        {:two_pair,
         [
           card(:ace, :hearts),
           card(:ace, :diamonds),
           card(:king, :clubs),
           card(:king, :spades),
           card(:queen, :hearts)
         ]}

      hand2 =
        {:two_pair,
         [
           card(:king, :hearts),
           card(:king, :diamonds),
           card(:queen, :clubs),
           card(:queen, :spades),
           card(:ace, :hearts)
         ]}

      # AA-KK vs KK-QQ - first hand wins on high pair
      assert HandEvaluator.compare_hands(hand1, hand2) == :greater
    end

    test "two pair with same high pair, different low pairs" do
      hand1 =
        {:two_pair,
         [
           card(:ace, :hearts),
           card(:ace, :diamonds),
           card(:king, :clubs),
           card(:king, :spades),
           card(:queen, :hearts)
         ]}

      hand2 =
        {:two_pair,
         [
           card(:ace, :clubs),
           card(:ace, :spades),
           card(:queen, :clubs),
           card(:queen, :spades),
           card(:king, :hearts)
         ]}

      # AA-KK vs AA-QQ - first hand wins on low pair
      assert HandEvaluator.compare_hands(hand1, hand2) == :greater
    end

    test "two pair with identical pairs, different kickers" do
      hand1 =
        {:two_pair,
         [
           card(:ace, :hearts),
           card(:ace, :diamonds),
           card(:king, :clubs),
           card(:king, :spades),
           card(:queen, :hearts)
         ]}

      hand2 =
        {:two_pair,
         [
           card(:ace, :clubs),
           card(:ace, :spades),
           card(:king, :hearts),
           card(:king, :diamonds),
           card(:jack, :clubs)
         ]}

      # AA-KK-Q vs AA-KK-J - first hand wins on kicker
      assert HandEvaluator.compare_hands(hand1, hand2) == :greater
    end

    test "three of a kind with different trips" do
      hand1 =
        {:three_of_a_kind,
         [
           card(:ace, :hearts),
           card(:ace, :diamonds),
           card(:ace, :clubs),
           card(:king, :spades),
           card(:queen, :hearts)
         ]}

      hand2 =
        {:three_of_a_kind,
         [
           card(:king, :hearts),
           card(:king, :diamonds),
           card(:king, :clubs),
           card(:ace, :spades),
           card(:queen, :clubs)
         ]}

      # AAA vs KKK - first hand wins on trips rank
      assert HandEvaluator.compare_hands(hand1, hand2) == :greater
    end

    test "three of a kind with same trips, different kickers" do
      hand1 =
        {:three_of_a_kind,
         [
           card(:ace, :hearts),
           card(:ace, :diamonds),
           card(:ace, :clubs),
           card(:king, :spades),
           card(:queen, :hearts)
         ]}

      hand2 =
        {:three_of_a_kind,
         [
           card(:ace, :clubs),
           card(:ace, :spades),
           card(:ace, :hearts),
           card(:king, :diamonds),
           card(:jack, :clubs)
         ]}

      # AAA-K-Q vs AAA-K-J - first hand wins on second kicker
      assert HandEvaluator.compare_hands(hand1, hand2) == :greater
    end

    test "full house with different trips" do
      hand1 =
        {:full_house,
         [
           card(:ace, :hearts),
           card(:ace, :diamonds),
           card(:ace, :clubs),
           card(:king, :spades),
           card(:king, :hearts)
         ]}

      hand2 =
        {:full_house,
         [
           card(:king, :hearts),
           card(:king, :diamonds),
           card(:king, :clubs),
           card(:ace, :spades),
           card(:ace, :clubs)
         ]}

      # AAA-KK vs KKK-AA - first hand wins on trips rank
      assert HandEvaluator.compare_hands(hand1, hand2) == :greater
    end

    test "full house with same trips, different pairs" do
      hand1 =
        {:full_house,
         [
           card(:ace, :hearts),
           card(:ace, :diamonds),
           card(:ace, :clubs),
           card(:king, :spades),
           card(:king, :hearts)
         ]}

      hand2 =
        {:full_house,
         [
           card(:ace, :clubs),
           card(:ace, :spades),
           card(:ace, :hearts),
           card(:queen, :diamonds),
           card(:queen, :clubs)
         ]}

      # AAA-KK vs AAA-QQ - first hand wins on pair rank
      assert HandEvaluator.compare_hands(hand1, hand2) == :greater
    end

    test "high card with multiple kicker comparisons" do
      hand1 =
        {:high_card,
         [
           card(:ace, :hearts),
           card(:king, :diamonds),
           card(:queen, :clubs),
           card(:jack, :spades),
           card(:nine, :hearts)
         ]}

      hand2 =
        {:high_card,
         [
           card(:ace, :clubs),
           card(:king, :spades),
           card(:queen, :hearts),
           card(:jack, :diamonds),
           card(:eight, :clubs)
         ]}

      # A-K-Q-J-9 vs A-K-Q-J-8 - first hand wins on fifth card
      assert HandEvaluator.compare_hands(hand1, hand2) == :greater
    end

    test "identical hands return equal" do
      hand1 =
        {:one_pair,
         [
           card(:ace, :hearts),
           card(:ace, :diamonds),
           card(:king, :clubs),
           card(:queen, :spades),
           card(:jack, :hearts)
         ]}

      hand2 =
        {:one_pair,
         [
           card(:ace, :clubs),
           card(:ace, :spades),
           card(:king, :hearts),
           card(:queen, :diamonds),
           card(:jack, :clubs)
         ]}

      assert HandEvaluator.compare_hands(hand1, hand2) == :equal
    end

    test "edge case: one pair with identical first three kickers" do
      # Test going deep into kicker comparison
      hand1 =
        {:one_pair,
         [
           card(:nine, :hearts),
           card(:nine, :diamonds),
           card(:ace, :clubs),
           card(:king, :spades),
           card(:eight, :hearts)
         ]}

      hand2 =
        {:one_pair,
         [
           card(:nine, :clubs),
           card(:nine, :spades),
           card(:ace, :hearts),
           card(:king, :diamonds),
           card(:seven, :clubs)
         ]}

      # 99-A-K-8 vs 99-A-K-7 - first hand wins on fourth kicker
      assert HandEvaluator.compare_hands(hand1, hand2) == :greater
    end

    test "edge case: three of a kind with identical first kicker" do
      hand1 =
        {:three_of_a_kind,
         [
           card(:nine, :hearts),
           card(:nine, :diamonds),
           card(:nine, :clubs),
           card(:ace, :spades),
           card(:eight, :hearts)
         ]}

      hand2 =
        {:three_of_a_kind,
         [
           card(:nine, :clubs),
           card(:nine, :spades),
           card(:nine, :hearts),
           card(:ace, :diamonds),
           card(:seven, :clubs)
         ]}

      # 999-A-8 vs 999-A-7 - first hand wins on second kicker
      assert HandEvaluator.compare_hands(hand1, hand2) == :greater
    end

    test "integration: evaluate_hand with kicker comparison" do
      # Test that kicker comparison works through the full evaluate_hand pipeline
      hole_cards1 = [card(:ace, :hearts), card(:king, :diamonds)]

      community1 = [
        card(:queen, :clubs),
        card(:jack, :spades),
        card(:ten, :hearts),
        card(:nine, :clubs),
        card(:eight, :diamonds)
      ]

      hole_cards2 = [card(:ace, :clubs), card(:king, :spades)]

      community2 = [
        card(:queen, :hearts),
        card(:jack, :diamonds),
        card(:ten, :clubs),
        card(:nine, :spades),
        card(:seven, :hearts)
      ]

      hand1 = HandEvaluator.evaluate_hand(hole_cards1, community1)
      hand2 = HandEvaluator.evaluate_hand(hole_cards2, community2)

      # Both should be straights (A-K-Q-J-10), but first has 8 as extra card vs 7
      # Since these are straights, the comparison should be equal
      assert HandEvaluator.compare_hands(hand1, hand2) == :equal
    end
  end

  describe "hand ranking order" do
    test "validates short deck hand ranking order" do
      # In short deck, flush beats full house
      hand_rankings = [
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

      assert HandEvaluator.hand_rankings() == hand_rankings
    end

    test "full house comparison: Bob KQ vs Alice QQ with community T T J T Q" do
      # Bob has K♠ Q♦
      bob_hole = [card(:king, :spades), card(:queen, :diamonds)]
      # Alice has Q♠ Q♣
      alice_hole = [card(:queen, :spades), card(:queen, :clubs)]
      
      # Community: T♥ T♦ J♠ T♣ Q♥
      community = [
        card(:ten, :hearts),
        card(:ten, :diamonds),
        card(:jack, :spades),
        card(:ten, :clubs),
        card(:queen, :hearts)
      ]

      bob_hand = HandEvaluator.evaluate_hand(bob_hole, community)
      alice_hand = HandEvaluator.evaluate_hand(alice_hole, community)

      # Both should have full houses
      assert elem(bob_hand, 0) == :full_house
      assert elem(alice_hand, 0) == :full_house

      # Alice should win (QQQ over TTT beats TTT over QQQ)
      assert HandEvaluator.compare_hands(alice_hand, bob_hand) == :greater
      assert HandEvaluator.compare_hands(bob_hand, alice_hand) == :less
    end
  end
end
