defmodule PokerServer.GameServer do
  use GenServer
  alias PokerServer.{GameState, BettingRound, Player, InputValidator, UIAdapter, Types}
  alias Phoenix.PubSub
  require Logger

  @type state :: %{
          game_id: String.t(),
          game_state: GameState.t(),
          betting_round: BettingRound.t() | nil,
          phase: Types.server_phase()
        }

  # Client API

  def start_link({game_id, players}) do
    GenServer.start_link(__MODULE__, {game_id, players},
      name: {:via, Registry, {PokerServer.GameRegistry, game_id}}
    )
  end

  @doc """
  Get the current game state
  """
  @spec get_state(GenServer.server()) :: state()
  def get_state(pid) do
    GenServer.call(pid, :get_state)
  end

  @doc """
  Process a player action (fold, call, raise, etc.)
  """
  @spec player_action(GenServer.server(), String.t(), Types.player_action()) ::
          {:ok, :action_processed | :betting_complete, state()} | {:error, term()}
  def player_action(pid, player_id, action) do
    GenServer.call(pid, {:player_action, player_id, action})
  end

  @doc """
  Start the next hand
  """
  @spec start_hand(GenServer.server()) :: {:ok, state()} | {:error, term()}
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
    # Set blind amounts in game state before starting hand
    game_state_with_blinds = %{game_state | small_blind: 10, big_blind: 20}
    updated_game_state = GameState.start_hand(game_state_with_blinds)

    # Create betting round for preflop
    betting_round =
      BettingRound.new(
        updated_game_state.players,
        # small blind - could be configurable
        10,
        # big blind - could be configurable  
        20,
        :preflop
      )

    new_state = %{
      state
      | game_state: updated_game_state,
        betting_round: betting_round,
        phase: :preflop_betting
    }

    broadcast_state_change(state.game_id, new_state)
    {:reply, {:ok, new_state}, new_state}
  end

  @impl true
  def handle_call(
        {:player_action, player_id, action},
        _from,
        %{betting_round: betting_round, phase: :preflop_betting} = state
      )
      when not is_nil(betting_round) do
    # Validate player exists in the game
    with :ok <- InputValidator.validate_player_exists(player_id, state.game_state.players),
         :ok <- InputValidator.validate_game_state(state.game_state) do
      case BettingRound.process_action(betting_round, player_id, action) do
        {:ok, updated_betting_round} ->
          new_state = %{state | betting_round: updated_betting_round}

          # Check if betting round is complete
          if BettingRound.betting_complete?(updated_betting_round) do
            # Move to next phase (flop betting)
            updated_game_state = GameState.deal_flop(state.game_state)

            # Create betting round for flop
            flop_betting_round =
              BettingRound.new(
                updated_game_state.players,
                0,
                0,
                :flop
              )

            final_state = %{
              new_state
              | game_state: updated_game_state,
                betting_round: flop_betting_round,
                phase: :flop_betting
            }

            broadcast_state_change(state.game_id, final_state)
            {:reply, {:ok, :betting_complete, final_state}, final_state}
          else
            broadcast_state_change(state.game_id, new_state)
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
  def handle_call(
        {:player_action, player_id, action},
        _from,
        %{betting_round: betting_round, phase: :flop_betting} = state
      )
      when not is_nil(betting_round) do
    # Validate player exists in the game
    with :ok <- InputValidator.validate_player_exists(player_id, state.game_state.players),
         :ok <- InputValidator.validate_game_state(state.game_state) do
      case BettingRound.process_action(betting_round, player_id, action) do
        {:ok, updated_betting_round} ->
          new_state = %{state | betting_round: updated_betting_round}

          # Check if betting round is complete
          if BettingRound.betting_complete?(updated_betting_round) do
            # Move to next phase (turn betting)
            updated_game_state = GameState.deal_turn(state.game_state)

            # Create betting round for turn
            turn_betting_round =
              BettingRound.new(
                updated_game_state.players,
                0,
                0,
                :turn
              )

            final_state = %{
              new_state
              | game_state: updated_game_state,
                betting_round: turn_betting_round,
                phase: :turn_betting
            }

            broadcast_state_change(state.game_id, final_state)
            {:reply, {:ok, :betting_complete, final_state}, final_state}
          else
            broadcast_state_change(state.game_id, new_state)
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
    {:reply, {:error, Types.error_no_active_betting_round()}, state}
  end

  @impl true
  def handle_info(message, state) do
    Logger.error("PokerServer.GameServer received unexpected message: #{inspect(message)}")
    {:noreply, state}
  end

  # Private Functions

  # TODO: Architectural smell - GameServer should not depend on UIAdapter (presentation layer)
  # This creates proper per-player filtering to prevent hole card leakage but violates separation of concerns
  # Future refactor: Move to dedicated GameBroadcaster service or event-based approach
  defp broadcast_state_change(game_id, new_state) do
    new_state.game_state.players
    |> Enum.each(fn player ->
      filtered_view = UIAdapter.get_broadcast_player_view(new_state, player.id)

      PubSub.broadcast(
        PokerServer.PubSub,
        "game:#{game_id}:#{player.id}",
        {:game_updated, filtered_view}
      )
    end)
  end
end
