defmodule PokerServer.UIAdapter do
  @moduledoc """
  Thin presentation layer between the poker service and UI frontends.

  Provides UI-ready data while keeping game logic in the service layer.
  Handles data filtering for anti-cheat and formats data for display.
  """

  alias PokerServer.{GameManager, BettingRound, HandEvaluator}

  @doc """
  Get filtered game state for a specific player.
  Returns only the data this player should see.
  """
  def get_player_view(game_id, player_id) do
    case GameManager.get_game_state(game_id) do
      {:ok, game_server_state} ->
        player_view = build_player_view(game_server_state, player_id)
        {:ok, player_view}

      error ->
        error
    end
  end

  @doc """
  Get UI-optimized player view from existing state for broadcasts.
  Returns flattened structure suitable for LiveView consumption while maintaining
  backward compatibility with existing broadcast expectations.
  """
  def get_broadcast_player_view(game_server_state, player_id) do
    # Build the UI-optimized view
    ui_view = build_player_view(game_server_state, player_id)

    # Add fields that broadcasts/tests expect for backward compatibility
    # Override phase with game_server_state.phase (includes betting state)
    enhanced_view =
      Map.merge(ui_view, %{
        game_id: game_server_state.game_id,
        # Use server phase (e.g., :preflop_betting)
        phase: game_server_state.phase,
        betting_round: game_server_state.betting_round,
        game_state: %{
          players: ui_view.players,
          hand_number: ui_view.hand_number,
          community_cards: ui_view.community_cards,
          pot: ui_view.pot,
          # Use game phase (e.g., :preflop)
          phase: game_server_state.game_state.phase
        }
      })

    enhanced_view
  end

  @doc """
  Format a card for display
  """
  def format_card(%{rank: rank, suit: suit}) do
    rank_str =
      case rank do
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

    suit_symbol =
      case suit do
        :hearts -> "♥"
        :diamonds -> "♦"
        :clubs -> "♣"
        :spades -> "♠"
      end

    %{
      display: "#{rank_str}#{suit_symbol}",
      color:
        case suit do
          :hearts -> "red-600"
          :diamonds -> "blue-600"
          :clubs -> "green-600"
          :spades -> "gray-900"
        end
    }
  end

  @doc """
  Check if a player can act in the current game state
  """
  def can_player_act?(game_server_state, player_id) do
    case game_server_state do
      # All betting phases from GameServer
      %{phase: phase, betting_round: betting_round}
      when phase in [:preflop_betting, :flop_betting, :turn_betting, :river_betting] and
             not is_nil(betting_round) ->
        active_player = BettingRound.get_active_player(betting_round)
        active_player && active_player.id == player_id

      # Non-betting phases from GameServer
      %{phase: :waiting_to_start} ->
        false

      %{phase: :flop} ->
        false

      %{phase: :turn} ->
        false

      %{phase: :river} ->
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

  def build_player_view(game_server_state, player_id, _game_id \\ nil) do
    game_state = game_server_state.game_state

    # Filter players to hide other players' hole cards 
    # Show cards only during true showdown (not when hand ended due to folds)
    is_hand_complete = game_state.phase == :hand_complete
    folded_players = get_folded_players(game_server_state)

    # Determine if this was a true showdown vs fold win
    # If hand is complete and there are folded players, check if only 1 player remains
    is_fold_win =
      is_hand_complete and
        MapSet.size(folded_players) > 0 and
        length(game_state.players) - MapSet.size(folded_players) <= 1

    filtered_players =
      Enum.map(game_state.players, fn player ->
        can_see_cards =
          player.id == player_id or
            (is_hand_complete and not is_fold_win and player.id not in folded_players)

        %{
          id: player.id,
          chips: get_effective_chips(game_server_state, player),
          position: player.position,
          hole_cards: if(can_see_cards, do: format_cards(player.hole_cards), else: []),
          is_current_player: player.id == player_id
        }
      end)

    # Get current player data
    current_player_data = Enum.find(filtered_players, & &1.is_current_player)

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
      pot: get_current_pot(game_server_state),

      # Betting
      betting_info: betting_info,
      can_act: can_act,
      valid_actions: if(can_act, do: get_valid_actions(game_server_state, player_id), else: []),

      # UI helpers
      can_start_hand: can_start_hand?(game_state),
      is_waiting_for_players: game_state.phase == :waiting_for_players,

      # Showdown information
      showdown_results: get_showdown_results(game_server_state, filtered_players)
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
    # Can only start a new hand if the game isn't complete (more than 1 player has chips)
    players_with_chips = Enum.count(game_state.players, &(&1.chips > 0))

    (game_state.phase == :waiting_for_players or game_state.phase == :hand_complete) and
      length(game_state.players) >= 2 and
      players_with_chips > 1
  end

  # Get the set of players who folded during the current hand.
  # Returns empty set if no fold information available.
  defp get_folded_players(game_server_state) do
    case game_server_state do
      # If we have an active betting round, use its folded players
      %{betting_round: betting_round} when not is_nil(betting_round) ->
        betting_round.folded_players

      # If no betting round but we have preserved folded players (hand ended early)
      %{folded_players: folded_players} when not is_nil(folded_players) ->
        folded_players

      # Fallback to empty set
      _ ->
        MapSet.new()
    end
  end

  # Get the current pot amount, preferring betting round pot when active.
  defp get_current_pot(game_server_state) do
    case game_server_state.betting_round do
      nil -> game_server_state.game_state.pot
      betting_round -> betting_round.pot
    end
  end

  # Get effective chips for a player (current chips minus bets committed this round).
  defp get_effective_chips(_game_server_state, player) do
    # Player chips in GameState already reflect all committed bets
    # (blinds are deducted in GameState.start_hand, betting actions sync back via GameServer)
    player.chips
  end

  # Get showdown results for display during hand_complete phase.
  defp get_showdown_results(game_server_state, filtered_players) do
    game_state = game_server_state.game_state

    if game_state.phase == :hand_complete do
      # Check if this was a fold win - if so, don't show hand analysis
      current_player = Enum.find(filtered_players, & &1.is_current_player)
      current_player_id = if current_player, do: current_player.id, else: nil

      folded_players_count =
        Enum.count(filtered_players, fn player ->
          Enum.empty?(player.hole_cards) and player.id != current_player_id
        end)

      active_players_count = length(filtered_players) - folded_players_count

      is_fold_win = folded_players_count > 0 and active_players_count <= 1

      if is_fold_win do
        # For fold wins, the winner is the player who didn't fold
        # Find the player who is not in the folded players set
        folded_players = get_folded_players(game_server_state)

        winner_id =
          Enum.find(game_state.players, fn player ->
            player.id not in folded_players
          end)

        winner_ids = if winner_id, do: [winner_id.id], else: []

        %{
          winners: winner_ids,
          hand_descriptions: %{},
          player_hands: %{},
          is_fold_win: true
        }
      else
        # True showdown - evaluate hands normally
        # Get non-folded players with their original hole cards
        non_folded_players =
          game_state.players
          |> Enum.reject(fn player ->
            # Player is folded if they have no hole cards visible in filtered view
            filtered_player = Enum.find(filtered_players, &(&1.id == player.id))
            filtered_player && Enum.empty?(filtered_player.hole_cards)
          end)

        # Evaluate hands for all non-folded players
        player_hands =
          non_folded_players
          |> Enum.map(fn player ->
            hand_result =
              HandEvaluator.evaluate_hand(player.hole_cards, game_state.community_cards)

            {player.id, hand_result}
          end)

        # Determine winners
        winners = HandEvaluator.determine_winners(player_hands)

        # Create hand descriptions
        hand_descriptions =
          player_hands
          |> Enum.into(%{}, fn {player_id, {hand_type, _cards}} ->
            {player_id, format_hand_description(hand_type)}
          end)

        %{
          winners: winners,
          hand_descriptions: hand_descriptions,
          player_hands: Enum.into(player_hands, %{}),
          is_fold_win: false
        }
      end
    else
      nil
    end
  end

  # Format hand type into readable description
  defp format_hand_description(hand_type) do
    case hand_type do
      :straight_flush -> "Straight Flush"
      :four_of_a_kind -> "Four of a Kind"
      :flush -> "Flush"
      :full_house -> "Full House"
      :straight -> "Straight"
      :three_of_a_kind -> "Three of a Kind"
      :two_pair -> "Two Pair"
      :one_pair -> "One Pair"
      :high_card -> "High Card"
    end
  end
end
