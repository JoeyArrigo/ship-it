defmodule PokerServer.GameServer do
  use GenServer
  alias PokerServer.{GameState, BettingRound, Player, InputValidator, GameBroadcaster, Types}
  require Logger

  @type state :: %{
          game_id: String.t(),
          game_state: GameState.t(),
          betting_round: BettingRound.t() | nil,
          phase: Types.server_phase(),
          folded_players: MapSet.t(String.t())
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
      phase: :waiting_to_start,
      folded_players: MapSet.new()
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call(:start_hand, _from, %{game_state: game_state} = state) do
    # Set blind amounts in game state before starting hand (0 so GameState doesn't post blinds)
    game_state_with_blinds = %{game_state | small_blind: 0, big_blind: 0}
    updated_game_state = GameState.start_hand(game_state_with_blinds)

    # Create betting round for preflop - BettingRound handles actual blind posting
    betting_round =
      BettingRound.new(
        updated_game_state.players,
        # small blind - could be configurable
        10,
        # big blind - could be configurable  
        20,
        :preflop,
        updated_game_state.button_position
      )

    # Sync player chips from betting round back to game state (blinds are posted in BettingRound.new)
    synced_game_state = %{
      updated_game_state
      | players: betting_round.players,
        pot: betting_round.pot
    }

    new_state = %{
      state
      | game_state: synced_game_state,
        betting_round: betting_round,
        phase: :preflop_betting,
        folded_players: MapSet.new()
    }

    GameBroadcaster.broadcast_state_change(state.game_id, new_state)
    {:reply, {:ok, new_state}, new_state}
  end

  @impl true
  def handle_call(
        {:player_action, player_id, action},
        _from,
        %{betting_round: betting_round, phase: :preflop_betting} = state
      )
      when not is_nil(betting_round) do
    process_betting_phase_action(
      state,
      player_id,
      action,
      &GameState.deal_flop/1,
      :flop,
      :flop_betting
    )
  end

  @impl true
  def handle_call(
        {:player_action, player_id, action},
        _from,
        %{betting_round: betting_round, phase: :flop_betting} = state
      )
      when not is_nil(betting_round) do
    process_betting_phase_action(
      state,
      player_id,
      action,
      &GameState.deal_turn/1,
      :turn,
      :turn_betting
    )
  end

  @impl true
  def handle_call(
        {:player_action, player_id, action},
        _from,
        %{betting_round: betting_round, phase: :turn_betting} = state
      )
      when not is_nil(betting_round) do
    process_betting_phase_action(
      state,
      player_id,
      action,
      &GameState.deal_river/1,
      :river,
      :river_betting
    )
  end

  @impl true
  def handle_call(
        {:player_action, player_id, action},
        _from,
        %{betting_round: betting_round, phase: :river_betting} = state
      )
      when not is_nil(betting_round) do
    process_betting_phase_action(
      state,
      player_id,
      action,
      # This function is never called for showdown due to special handling in process_betting_phase_action
      fn _game_state -> raise "This should never be called for showdown" end,
      nil,
      :hand_complete
    )
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

  # Private helper function for processing betting phase actions
  # Dialyzer incorrectly warns about unreachable error pattern - suppressing for this function
  @dialyzer {:nowarn_function, process_betting_phase_action: 6}
  defp process_betting_phase_action(
         state,
         player_id,
         action,
         next_game_state_fn,
         next_betting_round_type,
         next_phase
       ) do
    # Validate player exists in the game
    with :ok <- InputValidator.validate_player_exists(player_id, state.game_state.players),
         :ok <- InputValidator.validate_game_state(state.game_state) do
      case BettingRound.process_action(state.betting_round, player_id, action) do
        {:ok, updated_betting_round} ->
          # Sync updated player chips from betting round to game state
          synced_game_state = %{state.game_state | players: updated_betting_round.players}

          new_state = %{
            state
            | betting_round: updated_betting_round,
              game_state: synced_game_state
          }

          # Check if betting round is complete
          if BettingRound.betting_complete?(updated_betting_round) do
            # Check if only one player remains (others folded) - hand ends immediately
            active_players =
              length(updated_betting_round.players) -
                MapSet.size(updated_betting_round.folded_players)

            if active_players <= 1 do
              # Hand ends immediately, award pot to remaining player
              remaining_player_id =
                updated_betting_round.players
                |> Enum.find(fn player ->
                  player.id not in updated_betting_round.folded_players
                end)
                |> Map.get(:id)

              game_state_with_pot = %{synced_game_state | pot: updated_betting_round.pot}

              final_game_state =
                GameState.award_pot_to_winner(game_state_with_pot, remaining_player_id)

              final_state = %{
                new_state
                | game_state: final_game_state,
                  betting_round: nil,
                  phase: :hand_complete,
                  folded_players: updated_betting_round.folded_players
              }

              GameBroadcaster.broadcast_state_change(state.game_id, final_state)
              {:reply, {:ok, :betting_complete, final_state}, final_state}
            else
              # Continue to next phase
              game_state_with_pot = %{synced_game_state | pot: updated_betting_round.pot}

              # Handle showdown specially to pass folded players
              updated_game_state =
                if next_phase == :hand_complete do
                  # This is showdown - pass folded players
                  GameState.showdown(game_state_with_pot, updated_betting_round.folded_players)
                else
                  # Regular phase transition
                  next_game_state_fn.(game_state_with_pot)
                end

              # Create betting round for next phase (or nil for hand_complete)
              next_betting_round =
                if next_betting_round_type do
                  # Use new constructor that preserves existing pot without reposting blinds
                  # Also need to pass folded players to prevent them from acting
                  new_round =
                    BettingRound.new_from_existing(
                      updated_game_state.players,
                      updated_game_state.pot,
                      0,
                      next_betting_round_type,
                      updated_game_state.button_position
                    )

                  # Preserve folded players from previous round
                  %{new_round | folded_players: updated_betting_round.folded_players}
                else
                  nil
                end

              final_state = %{
                new_state
                | game_state: updated_game_state,
                  betting_round: next_betting_round,
                  phase: next_phase
              }

              GameBroadcaster.broadcast_state_change(state.game_id, final_state)
              {:reply, {:ok, :betting_complete, final_state}, final_state}
            end
          else
            GameBroadcaster.broadcast_state_change(state.game_id, new_state)
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
end
