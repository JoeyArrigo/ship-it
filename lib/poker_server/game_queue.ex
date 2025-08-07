defmodule PokerServer.GameQueue do
  @moduledoc """
  Global queue system for poker game matchmaking.
  Manages a single queue where players wait to be matched into games.
  """
  use GenServer
  alias Phoenix.PubSub
  alias PokerServer.GameManager

  defstruct waiting_players: [],
            min_players_per_game: 2,
            # Start with 2 for testing, will increase to 6 later
            max_players_per_game: 2

  # Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %__MODULE__{}, name: __MODULE__)
  end

  @doc """
  Add a player to the queue
  """
  def join_queue(player_name) do
    GenServer.call(__MODULE__, {:join_queue, player_name})
  end

  @doc """
  Remove a player from the queue
  """
  def leave_queue(player_name) do
    GenServer.call(__MODULE__, {:leave_queue, player_name})
  end

  @doc """
  Get current queue status
  """
  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  # Server Callbacks

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_call({:join_queue, player_name}, _from, state) do
    # Check if player is already in queue
    if Enum.any?(state.waiting_players, fn player -> player.name == player_name end) do
      {:reply, {:error, :already_in_queue}, state}
    else
      # Add player to queue
      new_player = %{
        name: player_name,
        joined_at: DateTime.utc_now()
      }

      updated_state = %{state | waiting_players: state.waiting_players ++ [new_player]}

      # Check if we can start a game
      final_state = maybe_start_game(updated_state)

      # Broadcast queue update
      broadcast_queue_update(final_state)

      {:reply, :ok, final_state}
    end
  end

  @impl true
  def handle_call({:leave_queue, player_name}, _from, state) do
    updated_players =
      Enum.reject(state.waiting_players, fn player -> player.name == player_name end)

    updated_state = %{state | waiting_players: updated_players}

    # Broadcast queue update
    broadcast_queue_update(updated_state)

    {:reply, :ok, updated_state}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      waiting_players: state.waiting_players,
      players_waiting_count: length(state.waiting_players)
    }

    {:reply, status, state}
  end

  # Private Functions

  defp maybe_start_game(state) do
    if length(state.waiting_players) >= state.min_players_per_game do
      # Take exactly the number of players needed for the game
      {game_players, remaining_players} =
        Enum.split(state.waiting_players, state.max_players_per_game)

      # Convert to the format expected by GameManager
      # Tournament structure: 1500 starting chips
      player_list = Enum.map(game_players, fn player -> {player.name, 1500} end)

      # Create the game
      case GameManager.create_game(player_list) do
        {:ok, game_id} ->
          # Auto-start the first hand immediately
          case GameManager.lookup_game(game_id) do
            {:ok, game_pid} ->
              PokerServer.GameServer.start_hand(game_pid)
              IO.puts("🚀 Auto-started hand for game #{game_id}")

            {:error, _reason} ->
              IO.puts("⚠️ Could not auto-start hand for game #{game_id}")
          end

          # Notify players they're in a game
          Enum.each(game_players, fn player ->
            IO.puts("🎮 Notifying player #{player.name} about game #{game_id}")
            PubSub.broadcast(PokerServer.PubSub, "player:#{player.name}", {:game_ready, game_id})
          end)

          %{state | waiting_players: remaining_players}

        {:error, _reason} ->
          # If game creation failed, keep players in queue
          state
      end
    else
      state
    end
  end

  defp broadcast_queue_update(state) do
    PubSub.broadcast(PokerServer.PubSub, "game_queue", {:queue_updated, state})
  end
end
