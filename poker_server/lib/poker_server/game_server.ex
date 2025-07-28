defmodule PokerServer.GameServer do
  use GenServer
  alias PokerServer.{GameState, BettingRound, Player, InputValidator}

  # Client API

  def start_link({game_id, players}) do
    GenServer.start_link(__MODULE__, {game_id, players}, 
      name: {:via, Registry, {PokerServer.GameRegistry, game_id}})
  end

  @doc """
  Get the current game state
  """
  def get_state(pid) do
    GenServer.call(pid, :get_state)
  end

  @doc """
  Process a player action (fold, call, raise, etc.)
  """
  def player_action(pid, player_id, action) do
    GenServer.call(pid, {:player_action, player_id, action})
  end

  @doc """
  Start the next hand
  """
  def start_hand(pid) do
    GenServer.call(pid, :start_hand)
  end

  # Server Callbacks

  @impl true
  def init({game_id, player_list}) do
    # Convert player info to Player structs with positions
    players = 
      player_list
      |> Enum.with_index()
      |> Enum.map(fn {{id, chips}, position} ->
        %Player{id: id, chips: chips, position: position, hole_cards: []}
      end)

    game_state = GameState.new(players)
    
    state = %{
      game_id: game_id,
      game_state: game_state,
      betting_round: nil,
      phase: :waiting_to_start
    }
    
    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call(:start_hand, _from, %{game_state: game_state} = state) do
    updated_game_state = GameState.start_hand(game_state)
    
    # Create betting round for preflop
    betting_round = BettingRound.new(
      updated_game_state.players, 
      10,  # small blind - could be configurable
      20,  # big blind - could be configurable  
      :preflop
    )
    
    new_state = %{state | 
      game_state: updated_game_state,
      betting_round: betting_round,
      phase: :preflop_betting
    }
    
    {:reply, {:ok, new_state}, new_state}
  end

  @impl true
  def handle_call({:player_action, player_id, action}, _from, 
    %{betting_round: betting_round, phase: :preflop_betting} = state) when not is_nil(betting_round) do
    
    # Validate player exists in the game
    with :ok <- InputValidator.validate_player_exists(player_id, state.game_state.players),
         :ok <- InputValidator.validate_game_state(state.game_state) do
      case BettingRound.process_action(betting_round, player_id, action) do
        {:ok, updated_betting_round} ->
          new_state = %{state | betting_round: updated_betting_round}
          
          # Check if betting round is complete
          if BettingRound.betting_complete?(updated_betting_round) do
            # Move to next phase (flop)
            updated_game_state = GameState.deal_flop(state.game_state)
            final_state = %{new_state | 
              game_state: updated_game_state, 
              betting_round: nil,
              phase: :flop
            }
            {:reply, {:ok, :betting_complete, final_state}, final_state}
          else
            {:reply, {:ok, :action_processed, new_state}, new_state}
          end
        
        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    else
      {:error, validation_error} -> 
        {:reply, {:error, {:invalid_input, validation_error}}, state}
    end
  end

  @impl true
  def handle_call({:player_action, _player_id, _action}, _from, state) do
    {:reply, {:error, :no_active_betting_round}, state}
  end
end