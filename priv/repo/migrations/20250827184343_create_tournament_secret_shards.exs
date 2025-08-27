defmodule PokerServer.Repo.Migrations.CreateTournamentSecretShards do
  use Ecto.Migration

  def change do
    create table(:tournament_secret_shards) do
      add :tournament_id, :text, null: false
      add :hand_number, :integer, null: false
      add :shard_index, :integer, null: false
      add :encrypted_shard_data, :binary, null: false
      add :shard_hash, :text, null: false
      add :key_version, :integer, null: false, default: 1

      timestamps()
    end

    # Ensure we have exactly 3 shards per tournament/hand combination
    create unique_index(:tournament_secret_shards, [:tournament_id, :hand_number, :shard_index])
    
    # Index for efficient lookups during recovery
    create index(:tournament_secret_shards, [:tournament_id, :hand_number])
  end
end