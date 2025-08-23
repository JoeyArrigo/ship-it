defmodule PokerServer.GameManager do
  use GenServer
  alias PokerServer.{GameServer, InputValidator}
  require Logger

  # Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Create a new poker game with the given players
  Returns {:ok, game_id} or {:error, reason}
  """
  def create_game(players) when is_list(players) do
    GenServer.call(__MODULE__, {:create_game, players})
  end

  @doc """
  Get the current state of a game
  """
  def get_game_state(game_id) do
    case Registry.lookup(PokerServer.GameRegistry, game_id) do
      [{pid, _}] -> {:ok, GameServer.get_state(pid)}
      [] -> {:error, :game_not_found}
    end
  end

  @doc """
  Process a player action in a game
  """
  def player_action(game_id, player_id, action) do
    with :ok <- InputValidator.validate_player_id(player_id),
         :ok <- InputValidator.validate_action(action) do
      case Registry.lookup(PokerServer.GameRegistry, game_id) do
        [{pid, _}] -> GameServer.player_action(pid, player_id, action)
        [] -> {:error, :game_not_found}
      end
    else
      {:error, validation_error} -> {:error, {:invalid_input, validation_error}}
    end
  end

  @doc """
  Lookup a game process by game ID
  Returns {:ok, pid} or {:error, :game_not_found}
  """
  def lookup_game(game_id) do
    case Registry.lookup(PokerServer.GameRegistry, game_id) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :game_not_found}
    end
  end

  @doc """
  List all active games
  """
  def list_games do
    GenServer.call(__MODULE__, :list_games)
  end

  # Server Callbacks

  @impl true
  def init(_state) do
    # Initialize state with games map and monitor refs
    initial_state = %{
      games: %{},
      monitors: %{}
    }

    {:ok, initial_state}
  end

  @impl true
  def handle_call({:create_game, players}, _from, state) do
    case InputValidator.validate_players(players) do
      {:ok, validated_players} ->
        game_id = generate_game_id()

        case start_game_process(game_id, validated_players) do
          {:ok, pid} ->
            # Monitor the game process for cleanup
            monitor_ref = Process.monitor(pid)

            game_info = %{
              pid: pid,
              players: validated_players,
              created_at: DateTime.utc_now()
            }

            updated_state = %{
              state
              | games: Map.put(state.games, game_id, game_info),
                monitors: Map.put(state.monitors, monitor_ref, game_id)
            }

            Logger.info("Created game #{game_id} with #{length(validated_players)} players")
            {:reply, {:ok, game_id}, updated_state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      {:error, validation_error} ->
        {:reply, {:error, {:invalid_input, validation_error}}, state}
    end
  end

  @impl true
  def handle_call(:list_games, _from, state) do
    games = Map.keys(state.games)
    {:reply, games, state}
  end

  @impl true
  def handle_info({:DOWN, monitor_ref, :process, _pid, reason}, state) do
    case Map.get(state.monitors, monitor_ref) do
      nil ->
        # Unknown monitor ref, ignore
        {:noreply, state}

      game_id ->
        Logger.info("Game #{game_id} process terminated with reason: #{inspect(reason)}")

        # Clean up both games and monitors maps
        updated_state = %{
          state
          | games: Map.delete(state.games, game_id),
            monitors: Map.delete(state.monitors, monitor_ref)
        }

        {:noreply, updated_state}
    end
  end

  @impl true
  def handle_info(message, state) do
    Logger.warning("GameManager received unexpected message: #{inspect(message)}")
    {:noreply, state}
  end

  # Private Functions

  defp start_game_process(game_id, players) do
    PokerServer.TournamentSupervisor.start_tournament(game_id, players)
  end

  defp generate_game_id do
    :crypto.strong_rand_bytes(8) |> Base.encode64() |> binary_part(0, 8)
  end
end
