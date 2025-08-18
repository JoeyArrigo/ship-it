defmodule PokerServer.GameState do
  @moduledoc """
  Manages the overall state of a poker game across multiple hands.

  Key responsibilities:
  - Track players, positions, and chip counts
  - Handle deck management and card dealing
  - Manage game phases (waiting, dealing, showdown)  
  - Tournament progression and player elimination
  - Button position advancement

  State flow: new/1 -> start_hand/1 -> deal_flop/1 -> deal_turn/1 -> deal_river/1 -> showdown/1
  """

  alias PokerServer.{Deck, Player, Card, Types}

  @type t :: %__MODULE__{
          players: [Player.t()],
          community_cards: [Card.t()],
          pot: non_neg_integer(),
          phase: Types.game_state_phase(),
          hand_number: non_neg_integer(),
          deck: Deck.t(),
          button_position: non_neg_integer(),
          small_blind: non_neg_integer(),
          big_blind: non_neg_integer()
        }

  defstruct [
    :players,
    :community_cards,
    :pot,
    :phase,
    :hand_number,
    :deck,
    :button_position,
    :small_blind,
    :big_blind
  ]

  @doc """
  Create a new game state with the given players.

  Initializes a tournament with players in random seating order,
  fresh deck, and waiting phase.

  ## Parameters
  - players: List of Player structs
  - opts: Optional keyword list
    - button_position: Override random button placement (for testing)

  ## Returns
  GameState struct ready for tournament play
  """
  def new(players, opts \\ []) do
    # Assign positions to players
    players_with_positions =
      players
      |> Enum.with_index()
      |> Enum.map(fn {player, index} -> %{player | position: index} end)

    button_position =
      case Keyword.get(opts, :button_position) do
        nil -> Enum.random(0..(length(players) - 1))
        pos when is_integer(pos) and pos >= 0 and pos < length(players) -> pos
        _ -> raise ArgumentError, "button_position must be a valid player position"
      end

    %__MODULE__{
      players: players_with_positions,
      phase: :waiting_for_players,
      hand_number: 0,
      pot: 0,
      community_cards: [],
      button_position: button_position,
      deck: Deck.create()
    }
  end

  def tournament_complete?(game_state) do
    length(game_state.players) == 1
  end

  def eliminate_players(game_state) do
    remaining_players = Enum.filter(game_state.players, &(&1.chips > 0))

    # Find the current button player (if they survive)
    current_button_player =
      game_state.players
      |> Enum.find(&(&1.position == game_state.button_position))

    # Reassign positions to remaining players
    players_with_new_positions =
      remaining_players
      |> Enum.with_index()
      |> Enum.map(fn {player, index} -> %{player | position: index} end)

    # Calculate new button position
    new_button_position =
      calculate_new_button_position(
        current_button_player,
        players_with_new_positions,
        game_state.button_position,
        game_state.players
      )

    %{game_state | players: players_with_new_positions, button_position: new_button_position}
  end

  defp calculate_new_button_position(
         current_button_player,
         new_players,
         old_button_position,
         old_players
       ) do
    cond do
      # Case 1: Button player survived - follow them to their new position
      current_button_player != nil && current_button_player.chips > 0 ->
        surviving_button_player = Enum.find(new_players, &(&1.id == current_button_player.id))
        surviving_button_player.position

      # Case 2: Button player eliminated - advance to next surviving player
      true ->
        advance_button_to_next_survivor(old_button_position, old_players, new_players)
    end
  end

  defp advance_button_to_next_survivor(old_button_position, old_players, new_players) do
    # Find the next surviving player after the old button position
    old_player_count = length(old_players)

    # Check each position after the button until we find a survivor
    next_survivor_old_position =
      1..old_player_count
      |> Enum.reduce_while(nil, fn offset, _acc ->
        check_position = rem(old_button_position + offset, old_player_count)
        check_player = Enum.find(old_players, &(&1.position == check_position))

        if check_player && check_player.chips > 0 do
          {:halt, check_position}
        else
          {:cont, nil}
        end
      end)

    # Find where that surviving player ended up in the new positions
    if next_survivor_old_position do
      survivor_player = Enum.find(old_players, &(&1.position == next_survivor_old_position))
      new_survivor = Enum.find(new_players, &(&1.id == survivor_player.id))
      new_survivor.position
    else
      # Fallback: if something goes wrong, button goes to position 0
      0
    end
  end

  def reset_for_next_hand(game_state) do
    # Reset hand-specific state
    reset_players =
      Enum.map(game_state.players, fn player ->
        %{player | hole_cards: []}
      end)

    %{
      game_state
      | players: reset_players,
        community_cards: [],
        pot: 0,
        phase: :waiting_for_players,
        deck: Deck.create() |> Deck.shuffle()
    }
  end

  @doc """
  Start a new hand of poker.

  Advances button position, deals 2 hole cards to each player,
  posts blinds, and transitions to preflop phase.

  ## Parameters
  - game_state: Current game state

  ## Returns
  Updated game state ready for preflop betting

  ## Side effects
  - Advances button position
  - Deals fresh deck and hole cards
  - Posts small and big blinds
  - Updates pot with blind amounts
  """
  @spec start_hand(t()) :: t()
  def start_hand(game_state) do
    # Create fresh shuffled deck for new hand (as per poker rules)
    fresh_deck = Deck.create() |> Deck.shuffle()

    # Move button position
    player_count = length(game_state.players)
    new_button_position = rem(game_state.button_position + 1, player_count)

    # Determine blind positions based on player count
    {small_blind_position, big_blind_position} =
      if player_count == 2 do
        # Heads-up: button is small blind, other player is big blind
        big_blind_position = rem(new_button_position + 1, player_count)
        {new_button_position, big_blind_position}
      else
        # Multi-player: small blind is button + 1, big blind is button + 2
        small_blind_position = rem(new_button_position + 1, player_count)
        big_blind_position = rem(new_button_position + 2, player_count)
        {small_blind_position, big_blind_position}
      end

    # Deal 2 cards to each player and post blinds
    {updated_players, remaining_deck, pot} =
      Enum.reduce(game_state.players, {[], fresh_deck, 0}, fn player,
                                                              {acc_players, deck, pot_acc} ->
        {card1, deck1} = Deck.deal_card(deck)
        {card2, deck2} = Deck.deal_card(deck1)

        # Post blinds based on position
        {chips_after_blinds, pot_contribution} =
          cond do
            player.position == small_blind_position && game_state.small_blind &&
                game_state.small_blind > 0 ->
              actual_blind = min(player.chips, game_state.small_blind)
              {player.chips - actual_blind, actual_blind}

            player.position == big_blind_position && game_state.big_blind &&
                game_state.big_blind > 0 ->
              actual_blind = min(player.chips, game_state.big_blind)
              {player.chips - actual_blind, actual_blind}

            true ->
              {player.chips, 0}
          end

        updated_player = %{player | hole_cards: [card1, card2], chips: chips_after_blinds}
        {[updated_player | acc_players], deck2, pot_acc + pot_contribution}
      end)

    %{
      game_state
      | players: Enum.reverse(updated_players),
        deck: remaining_deck,
        phase: :preflop,
        hand_number: game_state.hand_number + 1,
        button_position: new_button_position,
        pot: pot,
        community_cards: []
    }
  end

  # Simple stub implementations for dealing functions
  def deal_flop(game_state) do
    # Burn 1 card, deal 3 to community
    {_burn_card, deck_after_burn} = Deck.deal_card(game_state.deck)
    {card1, deck1} = Deck.deal_card(deck_after_burn)
    {card2, deck2} = Deck.deal_card(deck1)
    {card3, deck3} = Deck.deal_card(deck2)

    %{game_state | community_cards: [card1, card2, card3], deck: deck3, phase: :flop}
  end

  def deal_turn(game_state) do
    # Burn 1 card, deal 1 to community
    {_burn_card, deck_after_burn} = Deck.deal_card(game_state.deck)
    {turn_card, remaining_deck} = Deck.deal_card(deck_after_burn)

    %{
      game_state
      | community_cards: game_state.community_cards ++ [turn_card],
        deck: remaining_deck,
        phase: :turn
    }
  end

  def deal_river(game_state) do
    # Burn 1 card, deal 1 to community
    {_burn_card, deck_after_burn} = Deck.deal_card(game_state.deck)
    {river_card, remaining_deck} = Deck.deal_card(deck_after_burn)

    %{
      game_state
      | community_cards: game_state.community_cards ++ [river_card],
        deck: remaining_deck,
        phase: :river
    }
  end

  @doc """
  Evaluate all player hands and determine winners.

  Compares all remaining players' hole cards against community cards
  using short deck poker hand rankings. Awards pot to winner(s) and
  transitions to hand complete phase.

  ## Parameters  
  - game_state: Current game state with community cards dealt
  - folded_players: MapSet of player IDs who have folded

  ## Returns
  Updated game state with:
  - Winners determined and chips awarded
  - Phase set to :hand_complete
  - Pot distributed to winning player(s)

  ## Notes
  Uses short deck hand evaluation where flush beats full house.
  Handles ties by splitting pot equally among winners.
  Folded players are excluded from hand evaluation and cannot win.
  """
  @spec showdown(t(), MapSet.t(String.t())) :: t()
  def showdown(game_state, folded_players) do
    alias PokerServer.HandEvaluator

    # Evaluate each player's hand, excluding folded players
    player_hands =
      game_state.players
      |> Enum.reject(fn player -> player.id in folded_players end)
      |> Enum.map(fn player ->
        hand = HandEvaluator.evaluate_hand(player.hole_cards, game_state.community_cards)
        {player.id, hand}
      end)

    # Determine winners
    winners = HandEvaluator.determine_winners(player_hands)

    # Distribute pot among winners
    pot_per_winner = div(game_state.pot, length(winners))

    updated_players =
      game_state.players
      |> Enum.map(fn player ->
        if player.id in winners do
          %{player | chips: player.chips + pot_per_winner}
        else
          player
        end
      end)

    %{game_state | players: updated_players, pot: 0, phase: :hand_complete}
  end

  @doc """
  Award pot to the last remaining player when all others have folded.

  This function handles the case where only one player remains active
  after all others have folded, eliminating the need for a showdown.

  ## Parameters
  - game_state: Current game state
  - winner_id: ID of the player who should win the pot

  ## Returns
  Updated game state with:
  - Pot awarded to the winner
  - Phase set to :hand_complete
  - Pot set to 0
  """
  @spec award_pot_to_winner(t(), String.t()) :: t()
  def award_pot_to_winner(game_state, winner_id) do
    updated_players =
      game_state.players
      |> Enum.map(fn player ->
        if player.id == winner_id do
          %{player | chips: player.chips + game_state.pot}
        else
          player
        end
      end)

    %{game_state | players: updated_players, pot: 0, phase: :hand_complete}
  end
end
