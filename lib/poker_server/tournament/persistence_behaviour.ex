defmodule PokerServer.Tournament.PersistenceBehaviour do
  @moduledoc """
  Behaviour contract for tournament persistence operations.
  
  This behavior enables clean separation between test and production environments:
  - Production: Synchronous, blocking persistence to ensure data consistency
  - Test: No-op implementation to avoid database coupling
  
  The interface ensures that persistence operations are either completely successful
  or fail fast, maintaining the requirement that persisted events ≥ game state.
  """

  @doc """
  Appends a new event to the tournament event store.
  Must be synchronous - returns {:ok, event} or {:error, reason}.
  """
  @callback append_event(tournament_id :: binary(), event_type :: String.t(), payload :: map()) ::
              {:ok, any()} | {:error, any()}

  @doc """
  Gets all events for a tournament in sequence order.
  """
  @callback get_all_events(tournament_id :: binary()) :: [any()]

  @doc """
  Gets events after a specific sequence number for replay from snapshots.
  """
  @callback get_events_after_sequence(tournament_id :: binary(), sequence :: integer()) :: [any()]

  @doc """
  Gets all tournament IDs that have persisted events.
  Used for recovery on system startup.
  """
  @callback get_all_tournament_ids() :: [binary()]

  @doc """
  Gets the latest sequence number for a tournament.
  Returns nil if no events exist.
  """
  @callback get_latest_sequence(tournament_id :: binary()) :: integer() | nil

  @doc """
  Stores card state securely using Shamir's Secret Sharing.
  """
  @callback store_card_secrets(tournament_id :: binary(), hand_number :: integer(), card_state :: any()) ::
              {:ok, any()} | {:error, any()}

  @doc """
  Creates or updates a tournament snapshot.
  """
  @callback create_snapshot(tournament_id :: binary(), game_state :: any(), sequence :: integer(), opts :: keyword()) ::
              {:ok, any()} | {:ok, :no_snapshot_needed} | {:error, any()}

  @doc """
  Gets the latest snapshot for a tournament.
  """
  @callback get_latest_snapshot(tournament_id :: binary()) :: {:ok, any()} | {:error, :not_found}

  @doc """
  Reconstructs card state from stored secret shards.
  """
  @callback reconstruct_card_state(tournament_id :: binary(), hand_number :: integer()) ::
              {:ok, any()} | {:error, any()}
end