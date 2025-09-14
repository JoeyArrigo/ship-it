defmodule PokerServer.Tournament.Recovery do
  @moduledoc """
  Handles recovery of tournament state from events and snapshots.
  
  This module implements the core recovery logic for tournaments after
  crashes or system restarts by replaying events from the last snapshot.
  """
  
  alias PokerServer.{GameState, Player}
  alias PokerServer.GameState.{SecureState, PrivateState}
  alias PokerServer.Security.CardSerializer
  require Logger

  # Get the configured persistence implementation
  @persistence_module Application.compile_env(:poker_server, :tournament_persistence)

  @doc """
  Recovers the complete state for a tournament including secure card state.
  
  Recovery strategy:
  1. Load the latest snapshot (if any)
  2. Load all events after the snapshot sequence
  3. Replay events on top of snapshot state
  4. Reconstruct card state from secret shards if mid-hand
  5. Return the reconstructed state with complete card information
  """
  def recover_tournament_state(tournament_id) do
    Logger.info("Starting recovery for tournament #{tournament_id}")
    
    case @persistence_module.get_latest_snapshot(tournament_id) do
      {:error, :not_found} ->
        Logger.info("No snapshots found for tournament #{tournament_id}, replaying from beginning")
        recover_with_card_state(tournament_id, &replay_from_beginning/1)
        
      {:ok, snapshot} ->
        Logger.info("Found snapshot at sequence #{snapshot.sequence} for tournament #{tournament_id}")
        
        # Note: For now, we'll trust the snapshot integrity since TestPersistence 
        # doesn't have snapshots anyway and ProductionPersistence uses existing logic
        recover_with_card_state(tournament_id, fn tid -> replay_from_snapshot(tid, snapshot) end)
    end
  end
  
  defp recover_with_card_state(tournament_id, recovery_fn) do
    case recovery_fn.(tournament_id) do
      {:ok, server_state} ->
        # Create secure state from recovered public data
        secure_state = SecureState.from_game_state(server_state.game_state)
        
        # Check if we're mid-hand and need to reconstruct private card state
        if needs_card_recovery?(server_state) do
          Logger.info("Tournament #{tournament_id} is mid-hand, reconstructing card state")
          reconstruct_secure_card_state(tournament_id, server_state, secure_state)
        else
          Logger.info("Tournament #{tournament_id} recovered, no card state needed")
          {:ok, server_state}
        end
        
      error ->
        error
    end
  end

  @doc """
  Checks if a tournament needs recovery (has persisted events).
  """
  def needs_recovery?(tournament_id) do
    case @persistence_module.get_all_events(tournament_id) do
      [] -> false
      _events -> true
    end
  end

  @doc """
  Lists all tournaments that may need recovery.
  This would typically be called on application startup.
  """
  def tournaments_requiring_recovery do
    Logger.info("Scanning for tournaments requiring recovery...")
    
    # Query all distinct tournament IDs that have persisted events
    # These are tournaments that were running when the server shut down
    tournament_ids = @persistence_module.get_all_tournament_ids()
    
    Logger.info("Found #{length(tournament_ids)} tournaments with events")
    tournament_ids
  end

  # Private functions

  defp replay_from_beginning(tournament_id) do
    events = @persistence_module.get_all_events(tournament_id)
    
    case events do
      [] ->
        {:error, :no_events_found}
        
      [first_event | rest_events] ->
        # Initialize state from the first event (tournament_created)
        case initialize_state_from_creation_event(first_event) do
          {:ok, initial_state} ->
            final_state = Enum.reduce(rest_events, initial_state, &apply_event_to_state/2)
            {:ok, final_state}
            
          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp replay_from_snapshot(tournament_id, snapshot) do
    events = @persistence_module.get_events_after_sequence(tournament_id, snapshot.sequence)
    
    # Start with the snapshot state
    initial_state = deserialize_state(snapshot.state)
    
    # Apply all events after the snapshot
    final_state = Enum.reduce(events, initial_state, &apply_event_to_state/2)
    
    {:ok, final_state}
  end

  defp initialize_state_from_creation_event(%{event_type: "tournament_created", payload: payload}) do
    players = Enum.map(payload["players"], fn player_data ->
      %Player{
        id: player_data["id"],
        chips: player_data["chips"],
        position: player_data["position"],
        hole_cards: []
      }
    end)
    
    game_state = GameState.new(players, button_position: payload["button_position"])
    
    initial_server_state = %{
      game_id: nil,  # Will be set by caller
      game_state: game_state,
      betting_round: nil,
      original_betting_round: nil,
      phase: :waiting_to_start,
      folded_players: MapSet.new(),
      all_in_players: MapSet.new()
    }
    
    {:ok, initial_server_state}
  end

  defp initialize_state_from_creation_event(_other_event) do
    {:error, :invalid_creation_event}
  end

  defp apply_event_to_state(%{event_type: event_type, payload: payload}, state) do
    case event_type do
      "tournament_created" ->
        # Already handled in initialization
        state
        
      "hand_started" ->
        # Update state to reflect hand start, including player chip updates
        updated_players = Enum.map(payload["players"], fn player_data ->
          %Player{
            id: player_data["id"],
            chips: player_data["chips"],
            position: player_data["position"],
            hole_cards: []
          }
        end)
        
        updated_game_state = %{
          state.game_state |
          hand_number: payload["hand_number"],
          button_position: payload["button_position"],
          players: updated_players
        }
        
        %{state | 
          game_state: updated_game_state,
          phase: :preflop_betting,
          folded_players: MapSet.new(),
          all_in_players: MapSet.new()
        }
        
      "player_folded" ->
        player_id = payload["player_id"]
        %{state | folded_players: MapSet.put(state.folded_players, player_id)}
        
      "player_called" ->
        # Update pot from the event payload
        updated_game_state = %{state.game_state | pot: payload["pot"]}
        %{state | game_state: updated_game_state}
        
      "player_raised" ->
        # Update pot from the event payload
        updated_game_state = %{state.game_state | pot: payload["pot"]}
        %{state | game_state: updated_game_state}
        
      "player_checked" ->
        # Update pot from the event payload (if provided)
        if payload["pot"] do
          updated_game_state = %{state.game_state | pot: payload["pot"]}
          %{state | game_state: updated_game_state}
        else
          state
        end
        
      "player_all_in" ->
        player_id = payload["player_id"]
        %{state | all_in_players: MapSet.put(state.all_in_players, player_id)}
        
      "hand_completed" ->
        %{state | phase: :hand_complete}
        
      "tournament_completed" ->
        %{state | phase: :tournament_complete}
        
      _ ->
        Logger.warning("Unknown event type during recovery: #{event_type}")
        state
    end
  end

  defp deserialize_state(serialized_state) do
    # Enhanced public state format with betting context
    players = Enum.map(serialized_state["players"] || [], fn player_data ->
      hole_cards = Enum.map(player_data["hole_cards"] || [], fn card_data ->
        %PokerServer.Card{
          rank: String.to_atom(card_data["rank"]),
          suit: String.to_atom(card_data["suit"])
        }
      end)
      
      %Player{
        id: player_data["id"],
        chips: player_data["chips"],
        position: player_data["position"],
        hole_cards: hole_cards
      }
    end)
    
    # Convert community cards back to Card structs
    community_cards = Enum.map(serialized_state["community_cards"] || [], fn card_data ->
      %PokerServer.Card{
        rank: String.to_atom(card_data["rank"]),
        suit: String.to_atom(card_data["suit"])
      }
    end)
    
    # Deck will be empty in public snapshots (reconstructed from secret shards if needed)
    deck = []
    
    game_state = %GameState{
      players: players,
      community_cards: community_cards,
      pot: serialized_state["pot"] || 0,
      phase: String.to_atom(serialized_state["phase"] || "waiting_to_start"),
      hand_number: serialized_state["hand_number"] || 0,
      deck: deck,
      button_position: serialized_state["button_position"] || 0,
      small_blind: serialized_state["small_blind"],
      big_blind: serialized_state["big_blind"]
    }
    
    # Reconstruct betting round from saved betting context
    betting_round = if serialized_state["betting_round_type"] do
      reconstruct_betting_round(
        players,
        serialized_state["current_bet"] || 0,
        String.to_atom(serialized_state["betting_round_type"]),
        serialized_state["active_player_id"],
        serialized_state["folded_players"] || [],
        serialized_state["all_in_players"] || [],
        serialized_state["player_bets"] || %{},
        serialized_state["pot"] || 0,
        serialized_state["button_position"] || 0,
        serialized_state["players_who_can_act"] || []
      )
    else
      nil
    end
    
    # Map game phase to server phase
    server_phase = case game_state.phase do
      :preflop -> :preflop_betting
      :flop -> :flop_betting  
      :turn -> :turn_betting
      :river -> :river_betting
      phase -> phase
    end
    
    %{
      game_id: nil,  # Will be set by recovery caller
      game_state: game_state,
      betting_round: betting_round,
      original_betting_round: nil,  # Could be added later if needed
      phase: server_phase,
      folded_players: MapSet.new(serialized_state["folded_players"] || []),
      all_in_players: MapSet.new(serialized_state["all_in_players"] || [])
    }
  end
  
  # Reconstructs a betting round from complete saved betting context.
  # This uses persisted players_who_can_act to maintain exact betting round integrity.
  defp reconstruct_betting_round(players, current_bet, round_type, active_player_id, folded_player_ids, all_in_player_ids, player_bets, pot, _button_position, players_who_can_act_list) do
    # Find active player index
    active_player_index = if active_player_id do
      Enum.find_index(players, fn player -> player.id == active_player_id end)
    else
      nil
    end
    
    # Convert to MapSets
    folded_players = MapSet.new(folded_player_ids)
    all_in_players = MapSet.new(all_in_player_ids)
    
    # Use persisted players_who_can_act (fixes recovery bug)
    players_who_can_act = MapSet.new(players_who_can_act_list)
    
    %PokerServer.BettingRound{
      players: players,
      small_blind: 10,  # Default - could be saved if needed
      big_blind: 20,    # Default - could be saved if needed  
      round_type: round_type,
      pot: pot,
      current_bet: current_bet,
      player_bets: player_bets,
      active_player_index: active_player_index,
      folded_players: folded_players,
      all_in_players: all_in_players,
      last_raise_size: 0,  # Could be calculated or saved
      players_who_can_act: players_who_can_act,
      last_raiser: nil     # Could be saved if needed
    }
  end

  
  # Card state recovery functions
  
  defp needs_card_recovery?(game_state) do
    # Need card recovery if we're in an active hand (not waiting_to_start or hand_complete)
    case game_state.phase do
      :waiting_to_start -> false
      :hand_complete -> false
      :tournament_complete -> false
      _ -> 
        # We're in an active betting phase, need card state
        game_state.game_state.hand_number > 0
    end
  end
  
  

  defp reconstruct_secure_card_state(tournament_id, server_state, secure_state) do
    hand_number = server_state.game_state.hand_number
    
    case @persistence_module.reconstruct_card_state(tournament_id, hand_number) do
      {:ok, compact_card_state} ->
        Logger.info("Successfully reconstructed card secrets for tournament #{tournament_id} hand #{hand_number}")
        
        # Deserialize the compact card state
        card_state = CardSerializer.deserialize_card_state(compact_card_state)
        
        # Create private state from reconstructed card data
        private_state = PrivateState.from_card_state(card_state)
        
        # Combine with public state to create complete secure state
        complete_secure_state = SecureState.with_private_state(secure_state, private_state)
        
        # Convert back to traditional GameState for compatibility
        case SecureState.to_game_state(complete_secure_state) do
          {:ok, reconstructed_game_state} ->
            final_server_state = %{server_state | game_state: reconstructed_game_state}
            
            Logger.info("Card state successfully integrated into tournament #{tournament_id}")
            {:ok, final_server_state}
            
          {:error, reason} ->
            Logger.error("Failed to reconstruct complete game state for tournament #{tournament_id}: #{inspect(reason)}")
            {:error, {:state_reconstruction_failed, reason}}
        end
        
      {:error, {:insufficient_shards, shard_count}} ->
        Logger.error("Insufficient shards (#{shard_count}) to reconstruct card state for tournament #{tournament_id}")
        Logger.error("Cannot safely continue tournament - card integrity compromised")
        {:error, :insufficient_card_shards}
        
      {:error, reason} ->
        Logger.error("Failed to reconstruct card state for tournament #{tournament_id}: #{inspect(reason)}")
        Logger.warning("Continuing recovery without card state - may affect game fairness")
        {:ok, server_state}  # Continue without card state rather than failing completely
    end
  end
end