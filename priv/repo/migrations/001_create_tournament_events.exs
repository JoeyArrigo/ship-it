defmodule PokerServer.Repo.Migrations.CreateTournamentEvents do
  use Ecto.Migration

  def change do
    create table(:tournament_event, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :tournament_id, :uuid, null: false
      add :sequence, :integer, null: false
      add :event_type, :string, null: false
      add :payload, :map, null: false
      add :occurred_at, :utc_datetime_usec, null: false

      timestamps()
    end

    create unique_index(:tournament_event, [:tournament_id, :sequence])
    create index(:tournament_event, [:tournament_id, :occurred_at])
  end
end