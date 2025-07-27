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
end