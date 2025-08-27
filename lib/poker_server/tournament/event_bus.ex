defmodule PokerServer.Tournament.EventBus do
  @moduledoc """
  Event bus for tournament-related events using Phoenix.PubSub.
  
  Provides clean separation between game logic and persistence/UI concerns.
  GameServer emits domain events, and separate handlers respond to them.
  
  Events:
  - tournament_created: When a new tournament starts
  - hand_started: When a new hand begins (includes card state)
  - player_action_taken: When a player makes an action
  - hand_completed: When a hand finishes
  - tournament_completed: When the tournament ends
  """
  
  alias Phoenix.PubSub
  
  @pubsub PokerServer.PubSub
  
  @doc """
  Emits a tournament event to all subscribed handlers.
  """
  @spec emit(String.t(), atom(), map()) :: :ok
  def emit(tournament_id, event_type, event_data) do
    event = %{
      tournament_id: tournament_id,
      event_type: event_type,
      event_data: event_data,
      timestamp: DateTime.utc_now()
    }
    
    # Broadcast to topic: "tournament_events:tournament_id"
    PubSub.broadcast(@pubsub, "tournament_events:#{tournament_id}", {:tournament_event, event})
  end
  
  @doc """
  Subscribes a process to tournament events for a specific tournament.
  """
  @spec subscribe(String.t()) :: :ok | {:error, term()}
  def subscribe(tournament_id) do
    PubSub.subscribe(@pubsub, "tournament_events:#{tournament_id}")
  end
  
  @doc """
  Subscribes a process to all tournament events (useful for global handlers).
  """
  @spec subscribe_all() :: :ok | {:error, term()}
  def subscribe_all do
    PubSub.subscribe(@pubsub, "tournament_events:*")
  end
  
  @doc """
  Unsubscribes from tournament events.
  """
  @spec unsubscribe(String.t()) :: :ok
  def unsubscribe(tournament_id) do
    PubSub.unsubscribe(@pubsub, "tournament_events:#{tournament_id}")
  end
  
  # Convenience functions for specific event types
  
  @doc """
  Emits a tournament_created event.
  """
  @spec tournament_created(String.t(), map()) :: :ok
  def tournament_created(tournament_id, data) do
    emit(tournament_id, :tournament_created, data)
  end
  
  @doc """
  Emits a hand_started event with game state including card information.
  """
  @spec hand_started(String.t(), map()) :: :ok
  def hand_started(tournament_id, data) do
    emit(tournament_id, :hand_started, data)
  end
  
  @doc """
  Emits a player_action_taken event.
  """
  @spec player_action_taken(String.t(), map()) :: :ok
  def player_action_taken(tournament_id, data) do
    emit(tournament_id, :player_action_taken, data)
  end
  
  @doc """
  Emits a hand_completed event.
  """
  @spec hand_completed(String.t(), map()) :: :ok
  def hand_completed(tournament_id, data) do
    emit(tournament_id, :hand_completed, data)
  end
  
  @doc """
  Emits a tournament_completed event.
  """
  @spec tournament_completed(String.t(), map()) :: :ok
  def tournament_completed(tournament_id, data) do
    emit(tournament_id, :tournament_completed, data)
  end
end