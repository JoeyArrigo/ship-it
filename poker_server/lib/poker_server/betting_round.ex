defmodule PokerServer.BettingRound do
  alias PokerServer.{Player, Types}
  
  @type t :: %__MODULE__{
    players: [Player.t()],
    small_blind: non_neg_integer(),
    big_blind: non_neg_integer(),
    round_type: Types.betting_round_type(),
    pot: non_neg_integer(),
    current_bet: non_neg_integer(),
    player_bets: %{String.t() => non_neg_integer()},
    active_player_index: non_neg_integer(),
    folded_players: MapSet.t(String.t()),
    all_in_players: MapSet.t(String.t()),
    last_raise_size: non_neg_integer() | nil,
    players_who_can_act: MapSet.t(String.t()),
    last_raiser: String.t() | nil
  }
  
  defstruct [:players, :small_blind, :big_blind, :round_type, :pot, :current_bet, :player_bets, :active_player_index, :folded_players, :all_in_players, :last_raise_size, :players_who_can_act, :last_raiser]

  @spec new([Player.t()], non_neg_integer(), non_neg_integer(), Types.betting_round_type()) :: t()
  def new(players, small_blind, big_blind, round_type) do
    # Validate betting round type
    Types.validate_betting_round_type!(round_type)
    
    # Post blinds - small blind is position 0, big blind is position 1
    
    # Update player chips after posting blinds
    updated_players = 
      players
      |> Enum.map(fn player ->
        cond do
          player.position == 0 -> %{player | chips: player.chips - small_blind}
          player.position == 1 -> %{player | chips: player.chips - big_blind}
          true -> player
        end
      end)
    
    # Initialize player bets map
    player_bets = 
      players
      |> Enum.map(fn player ->
        cond do
          player.position == 0 -> {player.id, small_blind}
          player.position == 1 -> {player.id, big_blind}
          true -> {player.id, 0}
        end
      end)
      |> Enum.into(%{})
    
    # Initialize players who can act - all active players except those who posted blinds have full option
    active_player_ids = Enum.map(players, & &1.id) |> MapSet.new()
    players_who_can_act = if round_type == :preflop do
      # In preflop, the big blind gets an option even after small blind calls
      active_player_ids
    else
      # Post-flop, all active players need to act
      active_player_ids
    end
    
    %__MODULE__{
      players: updated_players,
      small_blind: small_blind,
      big_blind: big_blind,
      round_type: round_type,
      pot: small_blind + big_blind,
      current_bet: big_blind,
      player_bets: player_bets,
      active_player_index: get_initial_active_player_index(players, round_type),
      folded_players: MapSet.new(),
      all_in_players: MapSet.new(),
      last_raise_size: big_blind,
      players_who_can_act: players_who_can_act,
      last_raiser: nil  # Initially no raiser beyond the big blind
    }
  end

  def valid_actions(betting_round) do
    active_player = get_active_player(betting_round)
    player_current_bet = betting_round.player_bets[active_player.id] || 0
    amount_to_call = betting_round.current_bet - player_current_bet
    
    actions = [:fold]  # Can always fold (unless already all-in)
    
    actions = 
      if amount_to_call > 0 do
        # There's a bet to call
        if active_player.chips >= amount_to_call do
          actions ++ [:call]
        else
          actions ++ [:all_in]  # Can't afford full call, can only go all-in
        end
      else
        # No bet to call, can check
        actions ++ [:check]
      end
    
    # Can raise if has enough chips for minimum raise
    min_raise_amount = minimum_raise(betting_round)
    total_to_raise = min_raise_amount - player_current_bet
    
    actions = 
      if active_player.chips >= total_to_raise do
        actions ++ [:raise]
      else
        # Can't afford full raise but might be able to go all-in
        if active_player.chips > amount_to_call do
          # Has more than call amount, can go all-in as a raise
          if :all_in not in actions, do: actions ++ [:all_in], else: actions
        else
          actions
        end
      end
    
    # Players can always go all-in if they have chips (unless already all-in)
    actions = 
      if active_player.chips > 0 && active_player.id not in betting_round.all_in_players do
        if :all_in not in actions, do: actions ++ [:all_in], else: actions
      else
        actions
      end
    
    actions
  end

  defp get_initial_active_player_index(players, round_type) do
    player_count = length(players)
    
    if player_count == 2 do
      # Heads-up rules
      case round_type do
        :preflop -> 0  # Small blind acts first pre-flop
        _ -> 1         # Big blind acts first post-flop
      end
    else
      # Multi-player: UTG (position after big blind) acts first
      2
    end
  end

  def get_active_player(betting_round) do
    # Handle case where active_player_index might be out of bounds
    player_count = length(betting_round.players)
    safe_index = rem(betting_round.active_player_index, player_count)
    Enum.at(betting_round.players, safe_index)
  end

  def minimum_raise(betting_round) do
    betting_round.current_bet + (betting_round.last_raise_size || betting_round.big_blind)
  end

  def process_action(betting_round, player_id, action) do
    # Validate it's the correct player's turn
    active_player = get_active_player(betting_round)
    if active_player.id != player_id do
      {:error, Types.error_not_your_turn()}
    else
      # Validate the action is allowed
      valid_actions = valid_actions(betting_round)
      action_type = elem(action, 0)
      
      if action_type in valid_actions do
        execute_action(betting_round, player_id, action)
      else
        {:error, Types.error_invalid_action()}
      end
    end
  end

  defp execute_action(betting_round, player_id, {:fold}) do
    # Ensure players_who_can_act is initialized as MapSet
    players_who_can_act = betting_round.players_who_can_act || MapSet.new()
    
    updated_round = %{betting_round | 
      folded_players: MapSet.put(betting_round.folded_players, player_id),
      players_who_can_act: MapSet.delete(players_who_can_act, player_id),
      active_player_index: next_active_player_index(betting_round)
    }
    {:ok, updated_round}
  end

  defp execute_action(betting_round, player_id, {:call}) do
    player = Enum.find(betting_round.players, &(&1.id == player_id))
    current_bet_amount = betting_round.player_bets[player_id] || 0
    call_amount = betting_round.current_bet - current_bet_amount
    
    # Validate player has enough chips to call
    if call_amount > player.chips do
      {:error, Types.error_insufficient_chips(call_amount, player.chips)}
    else
      # Update player chips
      updated_players = Enum.map(betting_round.players, fn p ->
        if p.id == player_id, do: %{p | chips: p.chips - call_amount}, else: p
      end)
      
      # Ensure players_who_can_act is initialized as MapSet
      players_who_can_act = betting_round.players_who_can_act || MapSet.new()
      
      # Update betting round
      updated_round = %{betting_round |
        players: updated_players,
        player_bets: Map.put(betting_round.player_bets, player_id, betting_round.current_bet),
        pot: betting_round.pot + call_amount,
        players_who_can_act: MapSet.delete(players_who_can_act, player_id),
        active_player_index: next_active_player_index(betting_round)
      }
      {:ok, updated_round}
    end
  end

  defp execute_action(betting_round, player_id, {:raise, raise_amount}) do
    player = Enum.find(betting_round.players, &(&1.id == player_id))
    current_bet_amount = betting_round.player_bets[player_id] || 0
    total_bet_amount = raise_amount - current_bet_amount
    
    # Validate raise amount meets minimum requirement
    min_raise = minimum_raise(betting_round)
    cond do
      raise_amount < min_raise ->
        {:error, Types.error_below_minimum_raise(raise_amount, min_raise)}
      
      total_bet_amount > player.chips ->
        {:error, Types.error_insufficient_chips_for_raise(total_bet_amount, player.chips)}
      
      true ->
        # Update player chips
        updated_players = Enum.map(betting_round.players, fn p ->
          if p.id == player_id, do: %{p | chips: p.chips - total_bet_amount}, else: p
        end)
        
        # When someone raises, all other active players get a chance to act again
        active_player_ids = betting_round.players
          |> Enum.map(& &1.id)
          |> Enum.reject(&(&1 in betting_round.folded_players))
          |> Enum.reject(&(&1 in betting_round.all_in_players))
          |> MapSet.new()
        
        new_players_who_can_act = MapSet.delete(active_player_ids, player_id)
        
        # Update betting round
        updated_round = %{betting_round |
          players: updated_players,
          current_bet: raise_amount,
          player_bets: Map.put(betting_round.player_bets, player_id, raise_amount),
          pot: betting_round.pot + total_bet_amount,
          last_raise_size: raise_amount - betting_round.current_bet,
          players_who_can_act: new_players_who_can_act,
          last_raiser: player_id,
          active_player_index: next_active_player_index(betting_round)
        }
        {:ok, updated_round}
    end
  end

  defp execute_action(betting_round, player_id, {:check}) do
    # Ensure players_who_can_act is initialized as MapSet
    players_who_can_act = betting_round.players_who_can_act || MapSet.new()
    
    updated_round = %{betting_round |
      players_who_can_act: MapSet.delete(players_who_can_act, player_id),
      active_player_index: next_active_player_index(betting_round)
    }
    {:ok, updated_round}
  end

  defp execute_action(betting_round, player_id, {:all_in}) do
    player = Enum.find(betting_round.players, &(&1.id == player_id))
    current_bet_amount = betting_round.player_bets[player_id] || 0
    all_in_amount = current_bet_amount + player.chips
    
    # Update player chips to 0
    updated_players = Enum.map(betting_round.players, fn p ->
      if p.id == player_id, do: %{p | chips: 0}, else: p
    end)
    
    # Check if this all-in is also a raise (above current bet)
    is_raise = all_in_amount > betting_round.current_bet
    
    # If it's a raise, other players get a chance to act again
    new_players_who_can_act = if is_raise do
      active_player_ids = betting_round.players
        |> Enum.map(& &1.id)
        |> Enum.reject(&(&1 in betting_round.folded_players))
        |> Enum.reject(&(&1 in betting_round.all_in_players))
        |> MapSet.new()
      MapSet.delete(active_player_ids, player_id)
    else
      MapSet.delete(betting_round.players_who_can_act, player_id)
    end
    
    # Update betting round
    updated_round = %{betting_round |
      players: updated_players,
      current_bet: if(is_raise, do: all_in_amount, else: betting_round.current_bet),
      player_bets: Map.put(betting_round.player_bets, player_id, all_in_amount),
      pot: betting_round.pot + player.chips,
      all_in_players: MapSet.put(betting_round.all_in_players, player_id),
      players_who_can_act: new_players_who_can_act,
      last_raiser: if(is_raise, do: player_id, else: betting_round.last_raiser),
      active_player_index: next_active_player_index(betting_round)
    }
    {:ok, updated_round}
  end

  defp next_active_player_index(betting_round) do
    # Simple implementation - just move to next player, wrapping around
    player_count = length(betting_round.players)
    rem(betting_round.active_player_index + 1, player_count)
  end

  def betting_complete?(betting_round) do
    # Check if only one player remains (others folded)
    active_players = length(betting_round.players) - MapSet.size(betting_round.folded_players)
    if active_players <= 1 do
      true
    else
      # Betting is complete when no players need to act
      MapSet.size(betting_round.players_who_can_act) == 0
    end
  end

  def side_pots(betting_round) do
    # Get all player bets sorted by amount
    player_bet_amounts = 
      betting_round.player_bets
      |> Enum.reject(fn {player_id, _} -> player_id in betting_round.folded_players end)
      |> Enum.map(fn {player_id, bet} -> {player_id, bet} end)
      |> Enum.sort_by(fn {_, bet} -> bet end)
    
    # If no all-in players, return main pot
    if MapSet.size(betting_round.all_in_players) == 0 do
      eligible_players = player_bet_amounts |> Enum.map(&elem(&1, 0)) |> MapSet.new()
      [%{amount: betting_round.pot, eligible_players: eligible_players}]
    else
      create_side_pots(player_bet_amounts, betting_round.all_in_players)
    end
  end

  defp create_side_pots(player_bets, _all_in_players) do
    # Get all unique bet amounts in ascending order (including all-in and non-all-in)
    bet_levels = 
      player_bets
      |> Enum.map(&elem(&1, 1))
      |> Enum.uniq()
      |> Enum.sort()
    
    # Create side pots layer by layer
    create_pot_layers(player_bets, bet_levels, 0, [])
  end

  defp create_pot_layers(_player_bets, [], _prev_level, pots), do: Enum.reverse(pots)
  
  defp create_pot_layers(player_bets, [current_level | remaining_levels], prev_level, pots) do
    # Calculate the pot amount for this layer
    layer_amount = current_level - prev_level
    
    # Find all players who can participate in this layer (bet >= current_level)
    eligible_players = 
      player_bets
      |> Enum.filter(fn {_, bet} -> bet >= current_level end)
      |> Enum.map(&elem(&1, 0))
      |> MapSet.new()
    
    # Calculate the total pot for this layer
    pot_amount = layer_amount * MapSet.size(eligible_players)
    
    # Create a pot if there are eligible players (even if amount is 0)
    new_pot = if MapSet.size(eligible_players) > 0 do
      [%{amount: pot_amount, eligible_players: eligible_players}]
    else
      []
    end
    
    create_pot_layers(player_bets, remaining_levels, current_level, new_pot ++ pots)
  end
end