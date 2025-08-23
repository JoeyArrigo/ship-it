defmodule PokerServer.Tournament.Event do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query
  alias PokerServer.Repo

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "tournament_event" do
    field :tournament_id, :binary_id
    field :sequence, :integer
    field :event_type, :string
    field :payload, :map
    field :occurred_at, :utc_datetime_usec

    timestamps()
  end

  @doc false
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:tournament_id, :sequence, :event_type, :payload, :occurred_at])
    |> validate_required([:tournament_id, :sequence, :event_type, :payload, :occurred_at])
    |> validate_inclusion(:event_type, valid_event_types())
    |> unique_constraint([:tournament_id, :sequence])
  end

  @doc """
  Appends a new event to the event store for a tournament.
  Automatically assigns the next sequence number.
  """
  def append(tournament_id, event_type, payload) do
    next_sequence = get_next_sequence(tournament_id)
    
    %__MODULE__{}
    |> changeset(%{
      tournament_id: tournament_id,
      sequence: next_sequence,
      event_type: event_type,
      payload: payload,
      occurred_at: DateTime.utc_now()
    })
    |> Repo.insert()
  end

  @doc """
  Gets all events for a tournament in sequence order.
  """
  def get_all(tournament_id) do
    __MODULE__
    |> where([e], e.tournament_id == ^tournament_id)
    |> order_by([e], asc: e.sequence)
    |> Repo.all()
  end

  @doc """
  Gets events after a specific sequence number.
  Used for replaying from a snapshot.
  """
  def get_after_sequence(tournament_id, sequence) do
    __MODULE__
    |> where([e], e.tournament_id == ^tournament_id and e.sequence > ^sequence)
    |> order_by([e], asc: e.sequence)
    |> Repo.all()
  end

  @doc """
  Gets all tournament IDs that have persisted events.
  Used for recovery on system startup.
  """
  def get_all_tournament_ids do
    __MODULE__
    |> select([e], e.tournament_id)
    |> distinct(true)
    |> Repo.all()
  end

  @doc """
  Replays all events for a tournament to reconstruct state.
  """
  def replay(tournament_id, initial_state \\ nil) do
    events = get_all(tournament_id)
    
    events
    |> Enum.reduce(initial_state || new_tournament_state(), fn event, state ->
      apply_event(state, event)
    end)
  end

  defp get_next_sequence(tournament_id) do
    query = from e in __MODULE__,
      where: e.tournament_id == ^tournament_id,
      select: max(e.sequence)
    
    case Repo.one(query) do
      nil -> 1
      max_sequence -> max_sequence + 1
    end
  end

  defp valid_event_types do
    [
      # Tournament lifecycle
      "tournament_created",
      "tournament_started",
      "tournament_completed",
      "tournament_cancelled",
      
      # Player events
      "player_joined",
      "player_eliminated",
      "player_left",
      
      # Hand events
      "hand_started",
      "hand_completed",
      "cards_dealt",
      "community_cards_dealt",
      
      # Player actions
      "player_folded",
      "player_called",
      "player_raised",
      "player_checked",
      "player_all_in",
      
      # Betting rounds
      "betting_round_started",
      "betting_round_completed",
      
      # Other game events
      "blinds_posted",
      "pot_awarded",
      "side_pot_created"
    ]
  end

  defp new_tournament_state do
    # This would need to match your existing Tournament state structure
    # For now, returning a basic structure
    %{
      id: nil,
      status: :pending,
      players: [],
      current_hand: nil,
      event_count: 0
    }
  end

  defp apply_event(state, %__MODULE__{event_type: event_type, payload: payload}) do
    # This is where you'd apply each event type to transform the state
    # This will need to be implemented based on your Tournament module structure
    case event_type do
      "tournament_created" ->
        Map.merge(state, payload)
      
      "player_joined" ->
        player = payload["player"]
        %{state | players: [player | state.players]}
      
      "tournament_started" ->
        %{state | status: :active}
      
      "tournament_completed" ->
        %{state | status: :completed}
      
      # Add more event handlers as needed
      _ ->
        # Unknown event type, return state unchanged
        state
    end
    |> Map.put(:event_count, state.event_count + 1)
  end
end