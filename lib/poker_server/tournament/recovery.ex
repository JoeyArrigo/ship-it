defmodule PokerServer.Tournament.Recovery do
  @moduledoc """
  Handles recovery of tournament state from events and snapshots.
  
  This module implements the core recovery logic for tournaments after
  crashes or system restarts by replaying events from the last snapshot.
  """
  
  alias PokerServer.Tournament.{Event, Snapshot}
  alias PokerServer.{GameState, Player}
  require Logger

  @doc """
  Recovers the complete state for a tournament.
  
  Recovery strategy:
  1. Load the latest snapshot (if any)
  2. Load all events after the snapshot sequence
  3. Replay events on top of snapshot state
  4. Return the reconstructed state
  """
  def recover_tournament_state(tournament_id) do
    Logger.info("Starting recovery for tournament #{tournament_id}")
    
    case Snapshot.load_latest(tournament_id) do
      nil ->
        Logger.info("No snapshots found for tournament #{tournament_id}, replaying from beginning")
        replay_from_beginning(tournament_id)
        
      snapshot ->
        Logger.info("Found snapshot at sequence #{snapshot.sequence} for tournament #{tournament_id}")
        
        # Verify snapshot integrity
        if Snapshot.verify_integrity(snapshot) do
          replay_from_snapshot(tournament_id, snapshot)
        else
          Logger.error("Snapshot integrity check failed for tournament #{tournament_id}, falling back to full replay")
          replay_from_beginning(tournament_id)
        end
    end
  end

  @doc """
  Checks if a tournament needs recovery (has persisted events).
  """
  def needs_recovery?(tournament_id) do
    case Event.get_all(tournament_id) do
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
    tournament_ids = Event.get_all_tournament_ids()
    
    Logger.info("Found #{length(tournament_ids)} tournaments with events")
    tournament_ids
  end

  # Private functions

  defp replay_from_beginning(tournament_id) do
    events = Event.get_all(tournament_id)
    
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
    events = Event.get_after_sequence(tournament_id, snapshot.sequence)
    
    # Start with the snapshot state
    initial_state = deserialize_state(snapshot.state)
    
    # Apply all events after the snapshot
    final_state = Enum.reduce(events, initial_state, &apply_event_to_state/2)
    
    {:ok, final_state}
  end

  defp initialize_state_from_creation_event(%Event{event_type: "tournament_created", payload: payload}) do
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

  defp apply_event_to_state(%Event{event_type: event_type, payload: payload}, state) do
    case event_type do
      "tournament_created" ->
        # Already handled in initialization
        state
        
      "hand_started" ->
        # Update state to reflect hand start
        updated_game_state = %{
          state.game_state |
          hand_number: payload["hand_number"],
          button_position: payload["button_position"]
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
        # Update pot and player chips if needed
        # For now, just track the action occurred
        state
        
      "player_raised" ->
        # Update pot and player chips based on raise
        state
        
      "player_checked" ->
        # No state change needed for check
        state
        
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
    players = Enum.map(serialized_state["game_state"]["players"], fn player_data ->
      %Player{
        id: player_data["id"],
        chips: player_data["chips"],
        position: player_data["position"],
        hole_cards: player_data["hole_cards"] || []
      }
    end)
    
    game_state = %GameState{
      players: players,
      community_cards: serialized_state["game_state"]["community_cards"] || [],
      pot: serialized_state["game_state"]["pot"] || 0,
      phase: String.to_atom(serialized_state["game_state"]["phase"]),
      hand_number: serialized_state["game_state"]["hand_number"] || 0,
      deck: PokerServer.Deck.create(),  # Reconstruct deck - cards in play are tracked separately
      button_position: serialized_state["game_state"]["button_position"] || 0,
      small_blind: nil,
      big_blind: nil
    }
    
    %{
      game_id: serialized_state["game_id"],
      game_state: game_state,
      betting_round: nil,  # Betting rounds are reconstructed as needed
      original_betting_round: nil,
      phase: String.to_atom(serialized_state["phase"]),
      folded_players: MapSet.new(serialized_state["folded_players"] || []),
      all_in_players: MapSet.new(serialized_state["all_in_players"] || [])
    }
  end
end