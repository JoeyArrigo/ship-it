defmodule PokerServer.Repo.Migrations.AddCryptoMetadataToSecretShards do
  use Ecto.Migration

  def change do
    alter table(:tournament_secret_shards) do
      add :nonce, :binary, null: false
      add :encryption_key, :binary, null: false
    end
  end
end