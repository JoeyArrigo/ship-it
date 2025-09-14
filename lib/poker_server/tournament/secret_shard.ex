defmodule PokerServer.Tournament.SecretShard do
  @moduledoc """
  Ecto schema for storing encrypted card state shards.
  
  Each tournament hand's sensitive card information (hole cards, deck state) 
  is split into 3 shards using Shamir's Secret Sharing, where any 2 shards
  can reconstruct the original card state.
  """
  
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query
  
  alias PokerServer.Repo
  alias PokerServer.Security.ShamirSecretSharing
  
  @type t :: %__MODULE__{
    id: integer(),
    tournament_id: String.t(),
    hand_number: integer(),
    shard_index: integer(),
    encrypted_shard_data: binary(),
    shard_hash: String.t(),
    key_version: integer(),
    nonce: binary(),
    encryption_key: binary(),
    inserted_at: NaiveDateTime.t(),
    updated_at: NaiveDateTime.t()
  }
  
  schema "tournament_secret_shards" do
    field :tournament_id, :string
    field :hand_number, :integer
    field :shard_index, :integer
    field :encrypted_shard_data, :binary
    field :shard_hash, :string
    field :key_version, :integer, default: 1
    field :nonce, :binary
    field :encryption_key, :binary
    
    timestamps()
  end
  
  @doc false
  def changeset(secret_shard, attrs) do
    secret_shard
    |> cast(attrs, [:tournament_id, :hand_number, :shard_index, :encrypted_shard_data, :shard_hash, :key_version, :nonce, :encryption_key])
    |> validate_required([:tournament_id, :hand_number, :shard_index, :encrypted_shard_data, :shard_hash, :nonce, :encryption_key])
    |> validate_inclusion(:shard_index, [1, 2, 3])
    |> unique_constraint([:tournament_id, :hand_number, :shard_index])
  end
  
  @doc """
  Stores card state securely by splitting it into 3 shards.
  
  ## Parameters
  - tournament_id: Tournament identifier
  - hand_number: Hand number within the tournament  
  - card_state: Map containing sensitive card information
  
  ## Card State Structure
      %{
        hole_cards: %{"player1" => [card1, card2], "player2" => [card3, card4]},
        deck: [remaining_cards...],
        community_cards: [flop_cards...] # if any dealt
      }
  """
  @spec store_card_state(String.t(), integer(), map()) :: {:ok, [t()]} | {:error, term()}
  def store_card_state(tournament_id, hand_number, card_state) do
    # Serialize the card state
    serialized_state = :erlang.term_to_binary(card_state)
    
    case ShamirSecretSharing.split_secret(serialized_state) do
      {:ok, encrypted_shards} ->
        # Convert to database records
        shard_records = Enum.map(encrypted_shards, fn shard ->
          %__MODULE__{
            tournament_id: tournament_id,
            hand_number: hand_number,
            shard_index: shard.shard_index,
            encrypted_shard_data: shard.encrypted_data,
            shard_hash: shard.hash,
            key_version: 1,
            nonce: shard.nonce,
            encryption_key: shard.key
          }
        end)
        
        # Store all 3 shards in a transaction
        Repo.transaction(fn ->
          Enum.map(shard_records, &Repo.insert!/1)
        end)
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  @doc """
  Reconstructs card state from stored shards.
  
  Requires at least 2 out of 3 shards to reconstruct the original card state.
  """
  @spec reconstruct_card_state(String.t(), integer()) :: {:ok, map()} | {:error, term()}
  def reconstruct_card_state(tournament_id, hand_number) do
    query = from(s in __MODULE__,
      where: s.tournament_id == ^tournament_id and s.hand_number == ^hand_number,
      order_by: s.shard_index
    )
    
    case Repo.all(query) do
      shards when length(shards) >= 2 ->
        # Convert database records back to shard format
        encrypted_shards = Enum.map(shards, fn shard ->
          %{
            shard_index: shard.shard_index,
            encrypted_data: shard.encrypted_shard_data,
            nonce: shard.nonce,
            key: shard.encryption_key,
            hash: shard.shard_hash
          }
        end)
        
        case ShamirSecretSharing.reconstruct_secret(encrypted_shards) do
          {:ok, serialized_state} ->
            card_state = :erlang.binary_to_term(serialized_state)
            {:ok, card_state}
            
          {:error, reason} ->
            {:error, reason}
        end
        
      shards ->
        {:error, {:insufficient_shards, length(shards)}}
    end
  end
  
  @doc """
  Gets the latest hand number with stored card secrets for a tournament.
  """
  @spec get_latest_hand_number(String.t()) :: integer() | nil
  def get_latest_hand_number(tournament_id) do
    query = from(s in __MODULE__,
      where: s.tournament_id == ^tournament_id,
      select: max(s.hand_number)
    )
    
    Repo.one(query)
  end
  
  @doc """
  Verifies that all 3 shards exist for a given tournament/hand combination.
  """
  @spec verify_shard_completeness(String.t(), integer()) :: boolean()
  def verify_shard_completeness(tournament_id, hand_number) do
    query = from(s in __MODULE__,
      where: s.tournament_id == ^tournament_id and s.hand_number == ^hand_number,
      select: count()
    )
    
    Repo.one(query) == 3
  end
  
  @doc """
  Removes all shards for a tournament (cleanup after tournament completion).
  """
  @spec cleanup_tournament_shards(String.t()) :: {integer(), nil}
  def cleanup_tournament_shards(tournament_id) do
    query = from(s in __MODULE__, where: s.tournament_id == ^tournament_id)
    Repo.delete_all(query)
  end
  
  # Private helper functions - none needed since crypto metadata is stored in DB
end