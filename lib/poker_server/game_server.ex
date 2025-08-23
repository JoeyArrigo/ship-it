defmodule PokerServer.GameServer do
  use GenServer
  alias PokerServer.{GameState, BettingRound, Player, InputValidator, GameBroadcaster, Types}
  alias PokerServer.Tournament.{Event, Snapshot}
  require Logger

  @type state :: %{
          game_id: String.t(),
          game_state: GameState.t(),
          betting_round: BettingRound.t() | nil,
          original_betting_round: BettingRound.t() | nil,
          phase: Types.server_phase(),
          folded_players: MapSet.t(String.t()),
          all_in_players: MapSet.t(String.t())
        }

  # Client API

  def start_link({game_id, players}) do
    GenServer.start_link(__MODULE__, {game_id, players},
      name: {:via, Registry, {PokerServer.GameRegistry, game_id}}
    )
  end

  @doc """
  Start a GameServer with recovered state (used for tournament recovery)
  """
  def start_link({game_id, :recovered_state, recovered_state}) do
    GenServer.start_link(__MODULE__, {game_id, :recovered_state, recovered_state},
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

  @doc """
  End the game gracefully
  """
  @spec end_game(GenServer.server()) :: :ok
  def end_game(pid) do
    GenServer.cast(pid, :end_game)
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
      original_betting_round: nil,
      phase: :waiting_to_start,
      folded_players: MapSet.new(),
      all_in_players: MapSet.new()
    }

    # Persist tournament creation event
    persist_event(game_id, "tournament_created", %{
      "players" => Enum.map(players, fn p -> %{"id" => p.id, "chips" => p.chips, "position" => p.position} end),
      "button_position" => game_state.button_position
    })

    {:ok, state}
  end

  @impl true
  def init({game_id, :recovered_state, recovered_state}) do
    Logger.info("Starting GameServer #{game_id} with recovered state")
    
    # Use the recovered state directly, but ensure game_id is set
    state = Map.put(recovered_state, :game_id, game_id)
    
    Logger.info("GameServer #{game_id} recovered at phase: #{state.phase}, hand: #{state.game_state.hand_number}")
    
    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call(:start_hand, _from, %{game_state: game_state} = state) do
    # Check for tournament completion before starting a new hand
    # This is the appropriate time to check, not after every pot distribution
    if GameState.tournament_complete?(game_state) do
      Logger.info(
        "Tournament complete for game #{state.game_id}. Winner: #{hd(game_state.players).id}"
      )

      final_state = %{state | phase: :tournament_complete}

      # Schedule game termination after a brief delay
      Process.send_after(self(), :schedule_game_end, 5000)

      GameBroadcaster.broadcast_state_change(state.game_id, final_state)
      {:reply, {:ok, final_state}, final_state}
    else
      # Set blind amounts in game state before starting hand (0 so GameState doesn't post blinds)
      game_state_with_blinds = %{game_state | small_blind: 0, big_blind: 0}
      updated_game_state = GameState.start_hand(game_state_with_blinds)
      
      # Persist hand started event
      persist_event(state.game_id, "hand_started", %{
        "hand_number" => updated_game_state.hand_number,
        "button_position" => updated_game_state.button_position,
        "players" => Enum.map(updated_game_state.players, fn p -> 
          %{"id" => p.id, "chips" => p.chips, "position" => p.position}
        end)
      })

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
          original_betting_round: nil,
          phase: :preflop_betting,
          folded_players: MapSet.new(),
          all_in_players: MapSet.new()
      }

      GameBroadcaster.broadcast_state_change(state.game_id, new_state)
      {:reply, {:ok, new_state}, new_state}
    end
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
  def handle_cast(:end_game, state) do
    Logger.info("Game #{state.game_id} ending gracefully")
    GameBroadcaster.broadcast_state_change(state.game_id, %{state | phase: :game_ended})
    {:stop, :normal, state}
  end

  @impl true
  def handle_info(:schedule_game_end, state) do
    Logger.info("Ending game #{state.game_id} after tournament completion")
    {:stop, :normal, state}
  end

  @impl true
  def handle_info(message, state) do
    Logger.error("PokerServer.GameServer received unexpected message: #{inspect(message)}")
    {:noreply, state}
  end

  # Private Functions

  # Private helper function for processing betting phase actions
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
          # Persist player action event
          persist_player_action_event(state.game_id, player_id, action, updated_betting_round)
          
          process_successful_action(
            state,
            state.game_id,
            updated_betting_round,
            next_game_state_fn,
            next_betting_round_type,
            next_phase
          )

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    else
      {:error, validation_error} ->
        {:reply, {:error, {:invalid_input, validation_error}}, state}
    end
  end

  # Helper function to handle early hand termination when only one player remains
  defp handle_fold_win(state, game_id, updated_betting_round, synced_game_state) do
    remaining_player_id =
      updated_betting_round.players
      |> Enum.find(fn player ->
        player.id not in updated_betting_round.folded_players
      end)
      |> Map.get(:id)

    game_state_with_pot = %{synced_game_state | pot: updated_betting_round.pot}
    final_game_state = GameState.award_pot_to_winner(game_state_with_pot, remaining_player_id)

    final_state = %{
      state
      | game_state: final_game_state,
        betting_round: nil,
        phase: :hand_complete,
        folded_players: updated_betting_round.folded_players,
        all_in_players: updated_betting_round.all_in_players
    }

    GameBroadcaster.broadcast_state_change(game_id, final_state)
    {:reply, {:ok, :betting_complete, final_state}, final_state}
  end

  # Helper function to handle phase transitions and create next betting round
  defp handle_phase_transition(
         state,
         game_id,
         updated_betting_round,
         synced_game_state,
         next_game_state_fn,
         next_betting_round_type,
         next_phase
       ) do
    game_state_with_pot = %{synced_game_state | pot: updated_betting_round.pot}

    # Handle showdown specially to pass betting round for side pot calculation
    updated_game_state =
      if next_phase == :hand_complete do
        # This is showdown - use original betting round for proper side pot handling
        # The original betting round has the real bet amounts from when all-in first occurred
        betting_round_for_showdown = state.original_betting_round || updated_betting_round
        GameState.showdown(game_state_with_pot, betting_round_for_showdown)
      else
        # Regular phase transition
        next_game_state_fn.(game_state_with_pot)
      end

    # Create betting round for next phase (or nil for hand_complete)
    next_betting_round =
      create_next_betting_round(
        next_betting_round_type,
        updated_game_state,
        updated_betting_round.folded_players,
        updated_betting_round.all_in_players
      )

    intermediate_state = %{
      state
      | game_state: updated_game_state,
        betting_round: next_betting_round,
        phase: next_phase,
        folded_players: updated_betting_round.folded_players,
        all_in_players: updated_betting_round.all_in_players
    }

    # Check if the new betting round is immediately complete (all players all-in)
    # If so, recursively advance to next phase
    if next_betting_round != nil and BettingRound.betting_complete?(next_betting_round) do
      # Determine next phase progression based on current phase
      {next_next_game_state_fn, next_next_betting_round_type, next_next_phase} =
        case next_phase do
          :flop_betting ->
            {&GameState.deal_turn/1, :turn, :turn_betting}

          :turn_betting ->
            {&GameState.deal_river/1, :river, :river_betting}

          :river_betting ->
            {fn _game_state -> raise "This should never be called for showdown" end, nil,
             :hand_complete}

          :hand_complete ->
            {nil, nil, :hand_complete}
        end

      # For showdown, use the current betting round which has actual bet amounts
      # For other phases, pass the new betting round
      final_betting_round =
        if next_next_phase == :hand_complete do
          # For showdown, use the betting round that completed (has real bet amounts)
          updated_betting_round
        else
          next_betting_round
        end

      # Recursively advance to next phase
      handle_phase_transition(
        intermediate_state,
        game_id,
        final_betting_round,
        updated_game_state,
        next_next_game_state_fn,
        next_next_betting_round_type,
        next_next_phase
      )
    else
      GameBroadcaster.broadcast_state_change(game_id, intermediate_state)
      {:reply, {:ok, :betting_complete, intermediate_state}, intermediate_state}
    end
  end

  # Helper function to create the next betting round
  defp create_next_betting_round(nil, _updated_game_state, _folded_players, _all_in_players),
    do: nil

  defp create_next_betting_round(
         next_betting_round_type,
         updated_game_state,
         folded_players,
         all_in_players
       ) do
    # Use new constructor that preserves existing pot without reposting blinds
    # Also need to pass folded players to prevent them from acting
    new_round =
      BettingRound.new_from_existing(
        updated_game_state.players,
        updated_game_state.pot,
        0,
        next_betting_round_type,
        updated_game_state.button_position,
        folded_players,
        all_in_players
      )

    # folded_players and all_in_players are already set correctly by new_from_existing
    new_round
  end

  # Helper function to handle betting round completion
  defp handle_betting_completion(
         state,
         game_id,
         updated_betting_round,
         synced_game_state,
         next_game_state_fn,
         next_betting_round_type,
         next_phase
       ) do
    # Check if only one player remains (others folded) - hand ends immediately
    active_players =
      length(updated_betting_round.players) -
        MapSet.size(updated_betting_round.folded_players)

    if active_players <= 1 do
      handle_fold_win(state, game_id, updated_betting_round, synced_game_state)
    else
      handle_phase_transition(
        state,
        game_id,
        updated_betting_round,
        synced_game_state,
        next_game_state_fn,
        next_betting_round_type,
        next_phase
      )
    end
  end

  # Helper function to process successful betting action
  defp process_successful_action(
         state,
         game_id,
         updated_betting_round,
         next_game_state_fn,
         next_betting_round_type,
         next_phase
       ) do
    # Sync updated player chips from betting round to game state
    synced_game_state = %{state.game_state | players: updated_betting_round.players}

    # Store original betting round when betting is complete AND we have all-in players
    # This preserves the real bet amounts for side pot calculations
    original_betting_round =
      if state.original_betting_round == nil &&
           MapSet.size(updated_betting_round.all_in_players) > 0 &&
           BettingRound.betting_complete?(updated_betting_round) do
        # Store this as the source of truth for bet amounts
        updated_betting_round
      else
        state.original_betting_round
      end

    new_state = %{
      state
      | betting_round: updated_betting_round,
        original_betting_round: original_betting_round,
        game_state: synced_game_state
    }

    # Check if betting round is complete
    if BettingRound.betting_complete?(updated_betting_round) do
      handle_betting_completion(
        new_state,
        game_id,
        updated_betting_round,
        synced_game_state,
        next_game_state_fn,
        next_betting_round_type,
        next_phase
      )
    else
      GameBroadcaster.broadcast_state_change(game_id, new_state)
      {:reply, {:ok, :action_processed, new_state}, new_state}
    end
  end

  # Persistence helper functions

  defp persist_event(tournament_id, event_type, payload) do
    case Event.append(tournament_id, event_type, payload) do
      {:ok, _event} -> 
        :ok
      {:error, reason} ->
        Logger.error("Failed to persist event #{event_type} for tournament #{tournament_id}: #{inspect(reason)}")
        :error
    end
  end

  defp persist_player_action_event(tournament_id, player_id, action, betting_round) do
    event_type = case action do
      {:fold} -> "player_folded"
      {:call} -> "player_called" 
      {:raise, amount} -> "player_raised"
      {:check} -> "player_checked"
      {:all_in} -> "player_all_in"
      _ -> "player_action"
    end

    payload = case action do
      {:raise, amount} -> 
        %{"player_id" => player_id, "amount" => amount, "pot" => betting_round.pot}
      {:all_in} ->
        player = Enum.find(betting_round.players, &(&1.id == player_id))
        %{"player_id" => player_id, "amount" => player.chips, "pot" => betting_round.pot}
      _ ->
        %{"player_id" => player_id, "pot" => betting_round.pot}
    end

    persist_event(tournament_id, event_type, payload)
  end

  defp maybe_create_snapshot(tournament_id, state, sequence) do
    # Create snapshot at key moments or every 100 events
    case Snapshot.maybe_create_snapshot(tournament_id, serialize_state(state), sequence) do
      {:ok, _snapshot} ->
        Logger.debug("Created snapshot for tournament #{tournament_id} at sequence #{sequence}")
        :ok
      {:ok, :no_snapshot_needed} ->
        :ok
      {:error, reason} ->
        Logger.error("Failed to create snapshot for tournament #{tournament_id}: #{inspect(reason)}")
        :error
    end
  end

  defp serialize_state(state) do
    # Convert the current server state to a serializable format
    %{
      "game_id" => state.game_id,
      "phase" => state.phase,
      "game_state" => %{
        "players" => Enum.map(state.game_state.players, fn p ->
          %{
            "id" => p.id,
            "chips" => p.chips,
            "position" => p.position,
            "hole_cards" => p.hole_cards
          }
        end),
        "community_cards" => state.game_state.community_cards,
        "pot" => state.game_state.pot,
        "phase" => state.game_state.phase,
        "hand_number" => state.game_state.hand_number,
        "button_position" => state.game_state.button_position
      },
      "folded_players" => MapSet.to_list(state.folded_players),
      "all_in_players" => MapSet.to_list(state.all_in_players)
    }
  end
end
