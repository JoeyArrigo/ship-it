defmodule PokerServer.Repo.Migrations.CreateTournamentSnapshots do
  use Ecto.Migration

  def change do
    create table(:tournament_snapshot, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :tournament_id, :uuid, null: false
      add :sequence, :integer, null: false
      add :state, :map, null: false
      add :checksum, :string, null: false

      timestamps()
    end

    create unique_index(:tournament_snapshot, [:tournament_id, :sequence])
    create index(:tournament_snapshot, [:tournament_id, :inserted_at])
  end
end