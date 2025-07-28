defmodule PokerServer.GameManager do
  use GenServer
  alias PokerServer.{GameServer, InputValidator}

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
      [{pid, _}] -> GameServer.get_state(pid)
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
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_call({:create_game, players}, _from, state) do
    case InputValidator.validate_players(players) do
      {:ok, validated_players} ->
        game_id = generate_game_id()
        
        case start_game_process(game_id, validated_players) do
          {:ok, _pid} ->
            updated_state = Map.put(state, game_id, %{
              players: validated_players,
              created_at: DateTime.utc_now()
            })
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
    games = Map.keys(state)
    {:reply, games, state}
  end

  # Private Functions

  defp start_game_process(game_id, players) do
    DynamicSupervisor.start_child(
      PokerServer.GameSupervisor,
      {PokerServer.GameServer, {game_id, players}}
    )
  end

  defp generate_game_id do
    :crypto.strong_rand_bytes(8) |> Base.encode64() |> binary_part(0, 8)
  end
end