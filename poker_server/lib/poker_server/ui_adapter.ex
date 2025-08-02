defmodule PokerServer.UIAdapter do
  @moduledoc """
  Thin presentation layer between the poker service and UI frontends.
  
  Provides UI-ready data while keeping game logic in the service layer.
  Handles data filtering for anti-cheat and formats data for display.
  """
  
  alias PokerServer.{GameManager, BettingRound}

  @doc """
  Get filtered game state for a specific player.
  Returns only the data this player should see.
  """
  def get_player_view(game_id, player_id) do
    case GameManager.get_game_state(game_id) do
      {:ok, game_server_state} ->
        player_view = build_player_view(game_server_state, player_id)
        {:ok, player_view}
      
      error -> error
    end
  end

  @doc """
  Format a card for display
  """
  def format_card(%{rank: rank, suit: suit}) do
    rank_str = case rank do
      :ace -> "A"
      :king -> "K" 
      :queen -> "Q"
      :jack -> "J"
      :ten -> "10"
      :nine -> "9"
      :eight -> "8"
      :seven -> "7"
      :six -> "6"
      n when is_integer(n) -> to_string(n)
    end

    suit_symbol = case suit do
      :hearts -> "♥"
      :diamonds -> "♦"
      :clubs -> "♣"
      :spades -> "♠"
    end

    %{
      display: "#{rank_str}#{suit_symbol}",
      color: if(suit in [:hearts, :diamonds], do: "red", else: "black")
    }
  end

  @doc """
  Check if a player can act in the current game state
  """
  def can_player_act?(game_server_state, player_id) do
    case game_server_state do
      %{phase: phase, betting_round: betting_round} 
      when phase in [:preflop_betting, :flop_betting, :turn_betting, :river_betting] 
      and not is_nil(betting_round) ->
        active_player = BettingRound.get_active_player(betting_round)
        active_player && active_player.id == player_id
      
      # Handle other known phases explicitly
      %{phase: :waiting_to_start} ->
        false
      %{phase: :hand_complete} ->
        false
      %{phase: :showdown} ->
        false
      
      # Fallback for any unknown phases
      _ ->
        false
    end
  end

  @doc """
  Get valid actions for a player (wraps existing service logic)
  """
  def get_valid_actions(game_server_state, player_id) do
    case game_server_state do
      %{betting_round: betting_round} when not is_nil(betting_round) ->
        if can_player_act?(game_server_state, player_id) do
          BettingRound.valid_actions(betting_round)
        else
          []
        end
      _ ->
        []
    end
  end

  # Private Functions

  defp build_player_view(game_server_state, player_id) do
    game_state = game_server_state.game_state
    
    # Filter players to hide other players' hole cards
    filtered_players = Enum.map(game_state.players, fn player ->
      if player.id == player_id do
        # Current player can see their own cards
        %{
          id: player.id,
          chips: player.chips,
          position: player.position,
          hole_cards: format_cards(player.hole_cards),
          is_current_player: true
        }
      else
        # Other players' hole cards are hidden
        %{
          id: player.id,
          chips: player.chips,
          position: player.position,
          hole_cards: [],
          is_current_player: false
        }
      end
    end)

    # Get current player data
    current_player_data = Enum.find(filtered_players, &(&1.is_current_player))

    # Build betting info using existing service logic
    betting_info = get_betting_info(game_server_state, player_id)

    # Check if player can act
    can_act = can_player_act?(game_server_state, player_id)

    %{
      # Game info
      phase: game_state.phase,
      hand_number: game_state.hand_number,
      
      # Players
      players: filtered_players,
      current_player: current_player_data,
      
      # Cards and pot
      community_cards: format_cards(game_state.community_cards),
      pot: game_state.pot,
      
      # Betting
      betting_info: betting_info,
      can_act: can_act,
      valid_actions: if(can_act, do: get_valid_actions(game_server_state, player_id), else: []),
      
      # UI helpers
      can_start_hand: can_start_hand?(game_state),
      is_waiting_for_players: game_state.phase == :waiting_for_players
    }
  end

  defp format_cards(cards) when is_list(cards) do
    Enum.map(cards, &format_card/1)
  end

  # Use existing service logic for betting info
  defp get_betting_info(game_server_state, player_id) do
    case game_server_state do
      %{betting_round: betting_round} when not is_nil(betting_round) ->
        player_current_bet = betting_round.player_bets[player_id] || 0
        call_amount = max(0, betting_round.current_bet - player_current_bet)
        
        %{
          current_bet: betting_round.current_bet,
          pot: betting_round.pot,
          call_amount: call_amount,
          min_raise: BettingRound.minimum_raise(betting_round)
        }
      _ ->
        %{
          current_bet: 0,
          pot: game_server_state.game_state.pot,
          call_amount: 0,
          min_raise: 0
        }
    end
  end

  defp can_start_hand?(game_state) do
    game_state.phase == :waiting_for_players and length(game_state.players) >= 2
  end
end