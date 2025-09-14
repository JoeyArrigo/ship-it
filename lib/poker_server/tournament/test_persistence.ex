defmodule PokerServer.Tournament.TestPersistence do
  @moduledoc """
  Test implementation of the persistence behavior.
  
  This implementation provides no-op operations that return successful responses
  without any database interaction. This eliminates database coupling in tests
  while maintaining the same interface contract as production.
  
  All operations return immediately with :ok responses to allow game logic
  to continue normally during testing.
  """
  
  @behaviour PokerServer.Tournament.PersistenceBehaviour

  @impl true
  def append_event(_tournament_id, _event_type, _payload) do
    # Return a mock event structure that matches what tests might expect
    {:ok, %{id: "test-event-id", sequence: 1}}
  end

  @impl true
  def get_all_events(_tournament_id) do
    # Return empty list - tests don't rely on persisted events
    []
  end

  @impl true
  def get_events_after_sequence(_tournament_id, _sequence) do
    # Return empty list - tests don't rely on persisted events
    []
  end

  @impl true
  def get_all_tournament_ids() do
    # Return empty list - tests don't rely on persisted tournaments
    []
  end

  @impl true
  def get_latest_sequence(_tournament_id) do
    # Return nil - no persisted events in tests
    nil
  end

  @impl true
  def store_card_secrets(_tournament_id, _hand_number, _card_state) do
    # Return success - tests don't need actual secret storage
    {:ok, []}
  end

  @impl true
  def create_snapshot(_tournament_id, _game_state, _sequence, _opts) do
    # Return no snapshot needed - tests don't need persistence
    {:ok, :no_snapshot_needed}
  end

  @impl true
  def get_latest_snapshot(_tournament_id) do
    # Return not found - tests don't have persisted snapshots
    {:error, :not_found}
  end

  @impl true
  def reconstruct_card_state(_tournament_id, _hand_number) do
    # Return error - tests don't have persisted card secrets
    {:error, :not_found}
  end
end