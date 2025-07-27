defmodule PokerServer.GameState do
  alias PokerServer.Deck
  
  defstruct [:players, :community_cards, :pot, :phase, :hand_number, :deck, :button_position, :small_blind, :big_blind]

  def new(players) do
    %__MODULE__{
      players: players,
      phase: :waiting_for_players,
      hand_number: 0,
      pot: 0,
      community_cards: [],
      button_position: Enum.random(0..5),
      deck: Deck.create()
    }
  end

  def tournament_complete?(game_state) do
    length(game_state.players) == 1
  end

  def eliminate_players(game_state) do
    remaining_players = Enum.filter(game_state.players, &(&1.chips > 0))
    %{game_state | players: remaining_players}
  end

  def reset_for_next_hand(game_state) do
    # Reset hand-specific state
    reset_players = Enum.map(game_state.players, fn player ->
      %{player | hole_cards: []}
    end)
    
    %{game_state |
      players: reset_players,
      community_cards: [],
      pot: 0,
      phase: :waiting_for_players,
      deck: Deck.create() |> Deck.shuffle()
    }
  end

  # Stub implementation for start_hand - deal 2 hole cards to each player
  def start_hand(game_state) do
    # Deal 2 cards to each player
    {updated_players, remaining_deck} = 
      Enum.reduce(game_state.players, {[], game_state.deck}, fn player, {acc_players, deck} ->
        {card1, deck1} = Deck.deal_card(deck)
        {card2, deck2} = Deck.deal_card(deck1)
        updated_player = %{player | hole_cards: [card1, card2]}
        {[updated_player | acc_players], deck2}
      end)
    
    %{game_state |
      players: Enum.reverse(updated_players),
      deck: remaining_deck,
      phase: :preflop,
      hand_number: game_state.hand_number + 1
    }
  end

  # Simple stub implementations for dealing functions
  def deal_flop(game_state) do
    # Burn 1 card, deal 3 to community
    {_burn_card, deck_after_burn} = Deck.deal_card(game_state.deck)
    {card1, deck1} = Deck.deal_card(deck_after_burn)
    {card2, deck2} = Deck.deal_card(deck1)
    {card3, deck3} = Deck.deal_card(deck2)
    
    %{game_state |
      community_cards: [card1, card2, card3],
      deck: deck3,
      phase: :flop
    }
  end

  def deal_turn(game_state) do
    # Burn 1 card, deal 1 to community
    {_burn_card, deck_after_burn} = Deck.deal_card(game_state.deck)
    {turn_card, remaining_deck} = Deck.deal_card(deck_after_burn)
    
    %{game_state |
      community_cards: game_state.community_cards ++ [turn_card],
      deck: remaining_deck,
      phase: :turn
    }
  end

  def deal_river(game_state) do
    # Burn 1 card, deal 1 to community
    {_burn_card, deck_after_burn} = Deck.deal_card(game_state.deck)
    {river_card, remaining_deck} = Deck.deal_card(deck_after_burn)
    
    %{game_state |
      community_cards: game_state.community_cards ++ [river_card],
      deck: remaining_deck,
      phase: :river
    }
  end
end