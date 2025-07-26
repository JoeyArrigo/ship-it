defmodule PokerServer.DeckTest do
  use ExUnit.Case
  alias PokerServer.Deck

  describe "create/0" do
    test "creates a short deck with 36 cards" do
      deck = Deck.create()
      assert length(deck) == 36
    end

    test "contains all expected ranks (A, K, Q, J, 10, 9, 8, 7, 6)" do
      deck = Deck.create()
      ranks = deck |> Enum.map(& &1.rank) |> Enum.uniq() |> Enum.sort()
      expected_ranks = [:ace, :king, :queen, :jack, :ten, :nine, :eight, :seven, :six] |> Enum.sort()
      assert ranks == expected_ranks
    end

    test "contains all four suits" do
      deck = Deck.create()
      suits = deck |> Enum.map(& &1.suit) |> Enum.uniq() |> Enum.sort()
      expected_suits = [:clubs, :diamonds, :hearts, :spades] |> Enum.sort()
      assert suits == expected_suits
    end

    test "has exactly 4 cards of each rank" do
      deck = Deck.create()
      
      for rank <- [:ace, :king, :queen, :jack, :ten, :nine, :eight, :seven, :six] do
        count = deck |> Enum.count(fn card -> card.rank == rank end)
        assert count == 4, "Expected 4 cards of rank #{rank}, got #{count}"
      end
    end

    test "has exactly 9 cards of each suit" do
      deck = Deck.create()
      
      for suit <- [:clubs, :diamonds, :hearts, :spades] do
        count = deck |> Enum.count(fn card -> card.suit == suit end)
        assert count == 9, "Expected 9 cards of suit #{suit}, got #{count}"
      end
    end
  end

  describe "shuffle/1" do
    test "returns a deck with the same cards" do
      original_deck = Deck.create()
      shuffled_deck = Deck.shuffle(original_deck)
      
      assert length(shuffled_deck) == length(original_deck)
      assert Enum.sort(shuffled_deck) == Enum.sort(original_deck)
    end

    test "produces different order (probabilistic test)" do
      deck = Deck.create()
      shuffled = Deck.shuffle(deck)
      
      # Very unlikely that shuffle produces same order
      assert deck != shuffled
    end
  end

  describe "deal_card/1" do
    test "returns a card and remaining deck" do
      deck = Deck.create()
      {card, remaining_deck} = Deck.deal_card(deck)
      
      assert %{rank: _, suit: _} = card
      assert length(remaining_deck) == 35
      refute Enum.member?(remaining_deck, card)
    end

    test "fails when deck is empty" do
      empty_deck = []
      assert_raise ArgumentError, fn -> Deck.deal_card(empty_deck) end
    end
  end

  describe "deal_cards/2" do
    test "deals requested number of cards" do
      deck = Deck.create()
      {cards, remaining_deck} = Deck.deal_cards(deck, 5)
      
      assert length(cards) == 5
      assert length(remaining_deck) == 31
      
      # All dealt cards should be unique
      assert length(Enum.uniq(cards)) == 5
      
      # No dealt cards should remain in deck
      for card <- cards do
        refute Enum.member?(remaining_deck, card)
      end
    end

    test "fails when not enough cards in deck" do
      deck = Deck.create()
      assert_raise ArgumentError, fn -> Deck.deal_cards(deck, 37) end
    end

    test "deals zero cards returns empty list and original deck" do
      deck = Deck.create()
      {cards, remaining_deck} = Deck.deal_cards(deck, 0)
      
      assert cards == []
      assert remaining_deck == deck
    end
  end

  describe "cards_remaining/1" do
    test "returns number of cards in deck" do
      deck = Deck.create()
      assert Deck.cards_remaining(deck) == 36
      
      {_card, smaller_deck} = Deck.deal_card(deck)
      assert Deck.cards_remaining(smaller_deck) == 35
    end
  end
end