defmodule PokerServer.Tournament.ProductionPersistence do
  @moduledoc """
  Production implementation of the persistence behavior.
  
  This implementation provides synchronous, blocking persistence operations
  that ensure data consistency. All operations block until the database
  transaction is committed, maintaining the requirement that persisted events ≥ game state.
  """
  
  @behaviour PokerServer.Tournament.PersistenceBehaviour
  
  alias PokerServer.Tournament.{Event, Snapshot, SecretShard}
  require Logger

  @impl true
  def append_event(tournament_id, event_type, payload) do
    case Event.append(tournament_id, event_type, payload) do
      {:ok, event} ->
        Logger.debug("Successfully persisted #{event_type} for tournament #{tournament_id}")
        {:ok, event}
      {:error, reason} ->
        Logger.error("Failed to persist #{event_type} for tournament #{tournament_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def get_all_events(tournament_id) do
    Event.get_all(tournament_id)
  end

  @impl true
  def get_events_after_sequence(tournament_id, sequence) do
    Event.get_after_sequence(tournament_id, sequence)
  end

  @impl true
  def get_all_tournament_ids() do
    Event.get_all_tournament_ids()
  end

  @impl true
  def get_latest_sequence(tournament_id) do
    Event.get_latest_sequence(tournament_id)
  end

  @impl true
  def store_card_secrets(tournament_id, hand_number, card_state) do
    case SecretShard.store_card_state(tournament_id, hand_number, card_state) do
      {:ok, shards} ->
        Logger.debug("Successfully stored card secrets for tournament #{tournament_id} hand #{hand_number}")
        {:ok, shards}
      {:error, reason} ->
        Logger.error("Failed to store card secrets for tournament #{tournament_id} hand #{hand_number}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def create_snapshot(tournament_id, game_state, sequence, opts) do
    case Snapshot.maybe_create_snapshot(tournament_id, game_state, sequence, opts) do
      {:ok, snapshot} ->
        Logger.debug("Successfully created snapshot for tournament #{tournament_id} at sequence #{sequence}")
        {:ok, snapshot}
      {:ok, :no_snapshot_needed} = result ->
        result
      {:error, reason} ->
        Logger.error("Failed to create snapshot for tournament #{tournament_id} at sequence #{sequence}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def get_latest_snapshot(tournament_id) do
    case Snapshot.load_latest(tournament_id) do
      nil -> {:error, :not_found}
      snapshot -> {:ok, snapshot}
    end
  end

  @impl true
  def reconstruct_card_state(tournament_id, hand_number) do
    case SecretShard.reconstruct_card_state(tournament_id, hand_number) do
      {:ok, card_state} ->
        Logger.debug("Successfully reconstructed card state for tournament #{tournament_id} hand #{hand_number}")
        {:ok, card_state}
      {:error, reason} ->
        Logger.error("Failed to reconstruct card state for tournament #{tournament_id} hand #{hand_number}: #{inspect(reason)}")
        {:error, reason}
    end
  end
end