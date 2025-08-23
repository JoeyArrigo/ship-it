defmodule PokerServer.TournamentSupervisor do
  @moduledoc """
  Supervisor for managing tournament GameServer processes with recovery support.
  
  This supervisor handles:
  - Starting new tournaments
  - Recovering crashed tournaments from persisted state
  - Automatic recovery on application startup
  """
  
  use DynamicSupervisor
  alias PokerServer.Tournament.Recovery
  alias PokerServer.GameServer
  require Logger

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    Logger.info("Starting TournamentSupervisor")
    
    # Start recovery process for any active tournaments
    Task.start(fn -> recover_active_tournaments() end)
    
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Starts a new tournament with the given players.
  """
  def start_tournament(tournament_id, players) when is_list(players) do
    child_spec = %{
      id: GameServer,
      start: {GameServer, :start_link, [{tournament_id, players}]},
      restart: :transient
    }
    
    case DynamicSupervisor.start_child(__MODULE__, child_spec) do
      {:ok, pid} ->
        Logger.info("Started new tournament #{tournament_id} with #{length(players)} players")
        {:ok, pid}
        
      {:error, {:already_started, pid}} ->
        Logger.info("Tournament #{tournament_id} already running")
        {:ok, pid}
        
      {:error, reason} ->
        Logger.error("Failed to start tournament #{tournament_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Recovers and starts a tournament from persisted state.
  """
  def recover_tournament(tournament_id) do
    Logger.info("Attempting to recover tournament #{tournament_id}")
    
    case Recovery.recover_tournament_state(tournament_id) do
      {:ok, recovered_state} ->
        # Extract player information from recovered state
        players = Enum.map(recovered_state.game_state.players, fn player ->
          {player.id, player.chips}
        end)
        
        # Start the tournament with recovered players
        case start_tournament(tournament_id, players) do
          {:ok, pid} ->
            Logger.info("Successfully recovered tournament #{tournament_id}")
            {:ok, pid}
            
          {:error, reason} ->
            Logger.error("Failed to start recovered tournament #{tournament_id}: #{inspect(reason)}")
            {:error, reason}
        end
        
      {:error, :no_events_found} ->
        Logger.info("No events found for tournament #{tournament_id}, skipping recovery")
        {:ok, :no_recovery_needed}
        
      {:error, reason} ->
        Logger.error("Failed to recover tournament #{tournament_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Stops a specific tournament.
  """
  def stop_tournament(tournament_id) do
    case Registry.lookup(PokerServer.GameRegistry, tournament_id) do
      [{pid, _}] ->
        Logger.info("Stopping tournament #{tournament_id}")
        DynamicSupervisor.terminate_child(__MODULE__, pid)
        
      [] ->
        Logger.warning("Tournament #{tournament_id} not found for stopping")
        {:error, :not_found}
    end
  end

  @doc """
  Lists all currently running tournaments.
  """
  def list_active_tournaments do
    DynamicSupervisor.which_children(__MODULE__)
    |> Enum.map(fn {_, pid, :worker, [GameServer]} ->
      # Get tournament ID from the process
      case GameServer.get_state(pid) do
        %{game_id: game_id} -> {game_id, pid}
        _ -> {nil, pid}
      end
    end)
    |> Enum.filter(fn {game_id, _pid} -> game_id != nil end)
  end

  # Private functions

  defp recover_active_tournaments do
    Logger.info("Scanning for tournaments to recover...")
    
    tournaments = Recovery.tournaments_requiring_recovery()
    
    if length(tournaments) > 0 do
      Logger.info("Found #{length(tournaments)} tournaments requiring recovery")
      
      Enum.each(tournaments, fn tournament_id ->
        case recover_tournament(tournament_id) do
          {:ok, pid} when is_pid(pid) ->
            Logger.info("Successfully recovered tournament #{tournament_id}")
            
          {:ok, :no_recovery_needed} ->
            Logger.info("Tournament #{tournament_id} did not need recovery")
            
          {:error, reason} ->
            Logger.error("Failed to recover tournament #{tournament_id}: #{inspect(reason)}")
        end
      end)
    else
      Logger.info("No tournaments found requiring recovery")
    end
  end
end