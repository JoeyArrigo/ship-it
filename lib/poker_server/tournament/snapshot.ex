defmodule PokerServer.Tournament.Snapshot do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query
  alias PokerServer.Repo

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "tournament_snapshot" do
    field :tournament_id, :binary_id
    field :sequence, :integer
    field :state, :map
    field :checksum, :string

    timestamps()
  end

  @doc false
  def changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, [:tournament_id, :sequence, :state, :checksum])
    |> validate_required([:tournament_id, :sequence, :state, :checksum])
    |> unique_constraint([:tournament_id, :sequence])
  end

  @doc """
  Creates a new snapshot of tournament state at a specific sequence.
  """
  def create(tournament_id, state, sequence) do
    normalized_state = normalize_for_json(state)
    checksum = generate_checksum(state)
    
    %__MODULE__{}
    |> changeset(%{
      tournament_id: tournament_id,
      sequence: sequence,
      state: normalized_state,
      checksum: checksum
    })
    |> Repo.insert()
  end

  @doc """
  Loads the latest snapshot for a tournament.
  """
  def load_latest(tournament_id) do
    __MODULE__
    |> where([s], s.tournament_id == ^tournament_id)
    |> order_by([s], desc: s.sequence)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Loads a snapshot at or before a specific sequence.
  """
  def load_at_sequence(tournament_id, sequence) do
    __MODULE__
    |> where([s], s.tournament_id == ^tournament_id and s.sequence <= ^sequence)
    |> order_by([s], desc: s.sequence)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Gets all snapshots for a tournament, ordered by sequence.
  """
  def get_all(tournament_id) do
    __MODULE__
    |> where([s], s.tournament_id == ^tournament_id)
    |> order_by([s], asc: s.sequence)
    |> Repo.all()
  end

  @doc """
  Verifies the integrity of a snapshot using its checksum.
  """
  def verify_integrity(%__MODULE__{state: state, checksum: stored_checksum}) do
    computed_checksum = generate_checksum(state)
    computed_checksum == stored_checksum
  end

  @doc """
  Cleans up old snapshots, keeping only the most recent ones.
  By default, keeps the last 10 snapshots per tournament.
  """
  def cleanup_old_snapshots(tournament_id, keep_count \\ 10) do
    snapshots_to_keep = 
      __MODULE__
      |> where([s], s.tournament_id == ^tournament_id)
      |> order_by([s], desc: s.sequence)
      |> limit(^keep_count)
      |> select([s], s.id)
      |> Repo.all()

    __MODULE__
    |> where([s], s.tournament_id == ^tournament_id)
    |> where([s], s.id not in ^snapshots_to_keep)
    |> Repo.delete_all()
  end

  @doc """
  Creates a snapshot if certain conditions are met:
  - Every N events (default 100)
  - At key moments (hand completion, tournament start/end)
  """
  def maybe_create_snapshot(tournament_id, state, sequence, opts \\ []) do
    snapshot_interval = Keyword.get(opts, :snapshot_interval, 100)
    force = Keyword.get(opts, :force, false)
    
    should_snapshot = force or 
                      rem(sequence, snapshot_interval) == 0 or
                      is_key_moment?(state)
    
    if should_snapshot do
      create(tournament_id, state, sequence)
    else
      {:ok, :no_snapshot_needed}
    end
  end

  defp generate_checksum(state) do
    state
    |> normalize_for_json()
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode64()
  end

  # Convert MapSets and other non-JSON types to JSON-encodable formats
  defp normalize_for_json(%MapSet{} = mapset) do
    MapSet.to_list(mapset)
  end

  defp normalize_for_json(state) when is_struct(state) do
    # Convert struct to map, then normalize recursively
    state
    |> Map.from_struct()
    |> normalize_for_json()
  end

  defp normalize_for_json(state) when is_map(state) do
    state
    |> Enum.map(fn {key, value} -> {key, normalize_for_json(value)} end)
    |> Map.new()
  end

  defp normalize_for_json(value) when is_list(value) do
    Enum.map(value, &normalize_for_json/1)
  end

  defp normalize_for_json(value), do: value

  defp is_key_moment?(state) do
    # Define key moments when we always want a snapshot
    case Map.get(state, :phase) do
      :hand_complete -> true
      :waiting_for_players -> Map.get(state, :hand_number, 0) == 1  # Tournament start
      _ -> false
    end
  end
end