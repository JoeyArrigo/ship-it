defmodule PokerServer.GameLobby do
  @moduledoc """
  Manages game lobbies where players can join before the actual poker game starts.
  Acts as an intermediary between the web interface and the core poker game logic.
  """
  use GenServer
  alias Phoenix.PubSub

  defstruct [
    :id,
    :name,
    :max_players,
    :min_players,
    :status,
    :created_at,
    players: [],
    game_pid: nil
  ]

  # Client API

  def start_link({lobby_id, lobby_name}) do
    GenServer.start_link(__MODULE__, {lobby_id, lobby_name},
      name: {:via, Registry, {PokerServer.GameRegistry, lobby_id}}
    )
  end

  @doc """
  Add a player to the lobby
  """
  def add_player(lobby_id, player_name, chips \\ 1000) do
    case Registry.lookup(PokerServer.GameRegistry, lobby_id) do
      [{pid, _}] -> GenServer.call(pid, {:add_player, player_name, chips})
      [] -> {:error, :lobby_not_found}
    end
  end

  @doc """
  Remove a player from the lobby
  """
  def remove_player(lobby_id, player_name) do
    case Registry.lookup(PokerServer.GameRegistry, lobby_id) do
      [{pid, _}] -> GenServer.call(pid, {:remove_player, player_name})
      [] -> {:error, :lobby_not_found}
    end
  end

  @doc """
  Start the poker game (transition from lobby to actual game)
  """
  def start_game(lobby_id) do
    case Registry.lookup(PokerServer.GameRegistry, lobby_id) do
      [{pid, _}] -> GenServer.call(pid, :start_game)
      [] -> {:error, :lobby_not_found}
    end
  end

  @doc """
  Get the current lobby state
  """
  def get_state(lobby_id) do
    case Registry.lookup(PokerServer.GameRegistry, lobby_id) do
      [{pid, _}] -> GenServer.call(pid, :get_state)
      [] -> {:error, :lobby_not_found}
    end
  end

  @doc """
  Forward player action to the actual game (if started)
  """
  def player_action(lobby_id, player_name, action) do
    case Registry.lookup(PokerServer.GameRegistry, lobby_id) do
      [{pid, _}] -> GenServer.call(pid, {:player_action, player_name, action})
      [] -> {:error, :lobby_not_found}
    end
  end

  # Server Callbacks

  @impl true
  def init({lobby_id, lobby_name}) do
    state = %__MODULE__{
      id: lobby_id,
      name: lobby_name,
      max_players: 6,
      min_players: 2,
      status: :waiting_for_players,
      created_at: DateTime.utc_now(),
      players: [],
      game_pid: nil
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:add_player, player_name, chips}, _from, state) do
    cond do
      state.status != :waiting_for_players ->
        {:reply, {:error, :game_already_started}, state}

      length(state.players) >= state.max_players ->
        {:reply, {:error, :lobby_full}, state}

      Enum.any?(state.players, fn player -> player.name == player_name end) ->
        {:reply, {:error, :player_already_exists}, state}

      true ->
        new_player = %{
          name: player_name,
          chips: chips,
          position: length(state.players)
        }

        updated_state = %{state | players: state.players ++ [new_player]}

        # Broadcast the updated state
        broadcast_lobby_update(updated_state)

        {:reply, :ok, updated_state}
    end
  end

  @impl true
  def handle_call({:remove_player, player_name}, _from, state) do
    if state.status != :waiting_for_players do
      {:reply, {:error, :game_already_started}, state}
    else
      updated_players = Enum.reject(state.players, fn player -> player.name == player_name end)

      # Reassign positions
      updated_players_with_positions =
        updated_players
        |> Enum.with_index()
        |> Enum.map(fn {player, index} -> %{player | position: index} end)

      updated_state = %{state | players: updated_players_with_positions}

      # Broadcast the updated state
      broadcast_lobby_update(updated_state)

      {:reply, :ok, updated_state}
    end
  end

  @impl true
  def handle_call(:start_game, _from, state) do
    cond do
      state.status != :waiting_for_players ->
        {:reply, {:error, :game_already_started}, state}

      length(state.players) < state.min_players ->
        {:reply, {:error, :not_enough_players}, state}

      true ->
        # Convert lobby players to the format expected by GameServer
        game_players =
          state.players
          |> Enum.map(fn player -> {player.name, player.chips} end)

        # Start the actual poker game
        case DynamicSupervisor.start_child(
               PokerServer.GameSupervisor,
               {PokerServer.GameServer, {state.id, game_players}}
             ) do
          {:ok, game_pid} ->
            updated_state = %{state | status: :playing, game_pid: game_pid}

            # Broadcast the game start
            broadcast_lobby_update(updated_state)

            {:reply, :ok, updated_state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    # If game is running, get the actual game state
    if state.game_pid do
      game_server_state = PokerServer.GameServer.get_state(state.game_pid)
      # Merge lobby info with game state  
      combined_state = %{
        id: state.id,
        name: state.name,
        status: :playing,
        players: game_server_state.game_state.players,
        pot: game_server_state.game_state.pot,
        community_cards: game_server_state.game_state.community_cards,
        current_player_index: game_server_state.game_state.current_player_index,
        current_bet: game_server_state.game_state.current_bet,
        winner: game_server_state.game_state.winner
      }

      {:reply, {:ok, combined_state}, state}
    else
      # Return lobby state
      lobby_state = %{
        id: state.id,
        name: state.name,
        status: state.status,
        players: state.players,
        max_players: state.max_players,
        min_players: state.min_players,
        pot: 0,
        community_cards: [],
        current_player_index: nil,
        current_bet: 0,
        winner: nil
      }

      {:reply, {:ok, lobby_state}, state}
    end
  end

  @impl true
  def handle_call({:player_action, player_name, action}, _from, state) do
    if state.game_pid do
      # Forward to the actual game
      case PokerServer.GameServer.player_action(state.game_pid, player_name, action) do
        {:ok, _action_result, updated_game_state} ->
          # Broadcast the updated game state
          broadcast_game_update(state.id, updated_game_state)
          {:reply, :ok, state}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    else
      {:reply, {:error, :game_not_started}, state}
    end
  end

  # Private functions

  defp broadcast_lobby_update(state) do
    PubSub.broadcast(PokerServer.PubSub, "game:#{state.id}", {:lobby_updated, state})
  end

  defp broadcast_game_update(lobby_id, game_state) do
    PubSub.broadcast(PokerServer.PubSub, "game:#{lobby_id}", {:game_updated, game_state})
  end
end
