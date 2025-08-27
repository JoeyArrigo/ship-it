defmodule PokerServer.Tournament.PersistenceHandler do
  @moduledoc """
  Event handler for tournament persistence concerns.
  
  Listens to tournament events from EventBus and handles:
  - Event log persistence (existing Event system)
  - Card secret storage using Shamir's Secret Sharing  
  - Snapshot creation for recovery optimization
  
  This provides clean separation between game logic and persistence.
  """
  
  use GenServer
  
  alias PokerServer.Tournament.{EventBus, Event, Snapshot, SecretShard}
  alias PokerServer.Security.CardSerializer
  require Logger
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(_opts) do
    Logger.info("Starting Tournament PersistenceHandler")
    
    # Subscribe to all tournament events
    EventBus.subscribe_all()
    
    {:ok, %{}}
  end
  
  @impl true
  def handle_info({:tournament_event, event}, state) do
    handle_tournament_event(event)
    {:noreply, state}
  end
  
  @impl true
  def handle_info(message, state) do
    Logger.warning("PersistenceHandler received unexpected message: #{inspect(message)}")
    {:noreply, state}
  end
  
  # Private event handlers
  
  defp handle_tournament_event(%{tournament_id: tournament_id, event_type: event_type, event_data: data}) do
    case event_type do
      :tournament_created ->
        handle_tournament_created(tournament_id, data)
        
      :hand_started ->
        handle_hand_started(tournament_id, data)
        
      :player_action_taken ->
        handle_player_action_taken(tournament_id, data)
        
      :hand_completed ->
        handle_hand_completed(tournament_id, data)
        
      :tournament_completed ->
        handle_tournament_completed(tournament_id, data)
        
      _ ->
        Logger.warning("Unknown tournament event type: #{event_type}")
    end
  rescue
    error ->
      Logger.error("Error handling tournament event #{event_type} for #{tournament_id}: #{inspect(error)}")
  end
  
  defp handle_tournament_created(tournament_id, data) do
    Logger.debug("Persisting tournament_created event for #{tournament_id}")
    
    # Store in event log
    case Event.append(tournament_id, "tournament_created", %{
      "players" => data.players,
      "button_position" => data.button_position
    }) do
      {:ok, _event} -> 
        Logger.debug("Successfully persisted tournament_created for #{tournament_id}")
      {:error, reason} ->
        Logger.error("Failed to persist tournament_created for #{tournament_id}: #{inspect(reason)}")
    end
  end
  
  defp handle_hand_started(tournament_id, data) do
    Logger.debug("Persisting hand_started event and card secrets for #{tournament_id}")
    
    # 1. Store in event log (public information only - no cards)
    case Event.append(tournament_id, "hand_started", %{
      "hand_number" => data.hand_number,
      "button_position" => data.button_position,
      "players" => Enum.map(data.players, fn p -> 
        %{"id" => p.id, "chips" => p.chips, "position" => p.position}
      end)
    }) do
      {:ok, _event} -> 
        Logger.debug("Successfully persisted hand_started event for #{tournament_id}")
      {:error, reason} ->
        Logger.error("Failed to persist hand_started event for #{tournament_id}: #{inspect(reason)}")
    end
    
    # 2. Store card secrets securely
    if data.card_state do
      case store_card_secrets(tournament_id, data.hand_number, data.card_state) do
        {:ok, _shards} ->
          Logger.debug("Successfully stored card secrets for #{tournament_id} hand #{data.hand_number}")
        {:error, reason} ->
          Logger.error("Failed to store card secrets for #{tournament_id} hand #{data.hand_number}: #{inspect(reason)}")
      end
    end
  end
  
  defp handle_player_action_taken(tournament_id, data) do
    Logger.debug("Persisting player action for #{tournament_id}")
    
    event_type = case data.action do
      {:fold} -> "player_folded"
      {:call} -> "player_called" 
      {:raise, _amount} -> "player_raised"
      {:check} -> "player_checked"
      {:all_in} -> "player_all_in"
      _ -> "player_action"
    end

    payload = case data.action do
      {:raise, amount} -> 
        %{"player_id" => data.player_id, "amount" => amount, "pot" => data.pot}
      {:all_in} ->
        %{"player_id" => data.player_id, "amount" => data.player_chips, "pot" => data.pot}
      _ ->
        %{"player_id" => data.player_id, "pot" => data.pot}
    end

    case Event.append(tournament_id, event_type, payload) do
      {:ok, _event} -> 
        Logger.debug("Successfully persisted #{event_type} for #{tournament_id}")
      {:error, reason} ->
        Logger.error("Failed to persist #{event_type} for #{tournament_id}: #{inspect(reason)}")
    end
  end
  
  defp handle_hand_completed(tournament_id, data) do
    Logger.debug("Persisting hand_completed event for #{tournament_id}")
    
    case Event.append(tournament_id, "hand_completed", %{
      "hand_number" => data.hand_number,
      "winners" => data.winners || []
    }) do
      {:ok, _event} -> 
        Logger.debug("Successfully persisted hand_completed for #{tournament_id}")
      {:error, reason} ->
        Logger.error("Failed to persist hand_completed for #{tournament_id}: #{inspect(reason)}")
    end
  end
  
  defp handle_tournament_completed(tournament_id, data) do
    Logger.debug("Persisting tournament_completed event for #{tournament_id}")
    
    case Event.append(tournament_id, "tournament_completed", %{
      "winner" => data.winner,
      "final_standings" => data.final_standings || []
    }) do
      {:ok, _event} -> 
        Logger.debug("Successfully persisted tournament_completed for #{tournament_id}")
      {:error, reason} ->
        Logger.error("Failed to persist tournament_completed for #{tournament_id}: #{inspect(reason)}")
    end
  end
  
  # Helper function to store card secrets
  defp store_card_secrets(tournament_id, hand_number, card_state) do
    # Serialize card state to compact format
    compact_state = CardSerializer.serialize_card_state(card_state)
    
    # Store using Shamir's Secret Sharing
    SecretShard.store_card_state(tournament_id, hand_number, compact_state)
  end
end