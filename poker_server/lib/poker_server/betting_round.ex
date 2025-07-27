defmodule PokerServer.BettingRound do
  defstruct [:players, :small_blind, :big_blind, :round_type, :pot, :current_bet, :player_bets, :active_player_index, :folded_players, :all_in_players, :last_raise_size]

  def new(players, small_blind, big_blind, round_type) do
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
    
    %__MODULE__{
      players: updated_players,
      small_blind: small_blind,
      big_blind: big_blind,
      round_type: round_type,
      pot: small_blind + big_blind,
      current_bet: big_blind,
      player_bets: player_bets,
      active_player_index: (if length(players) > 2, do: 2, else: 0),  # UTG or small blind in heads-up
      folded_players: MapSet.new(),
      all_in_players: MapSet.new(),
      last_raise_size: big_blind
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
    
    actions
  end

  defp get_active_player(betting_round) do
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
      {:error, "not your turn"}
    else
      # Validate the action is allowed
      valid_actions = valid_actions(betting_round)
      action_type = elem(action, 0)
      
      if action_type in valid_actions do
        execute_action(betting_round, player_id, action)
      else
        {:error, "invalid action"}
      end
    end
  end

  defp execute_action(betting_round, player_id, {:fold}) do
    updated_round = %{betting_round | 
      folded_players: MapSet.put(betting_round.folded_players, player_id),
      active_player_index: next_active_player_index(betting_round)
    }
    {:ok, updated_round}
  end

  defp execute_action(betting_round, player_id, {:call}) do
    _player = Enum.find(betting_round.players, &(&1.id == player_id))
    current_bet_amount = betting_round.player_bets[player_id] || 0
    call_amount = betting_round.current_bet - current_bet_amount
    
    # Update player chips
    updated_players = Enum.map(betting_round.players, fn p ->
      if p.id == player_id, do: %{p | chips: p.chips - call_amount}, else: p
    end)
    
    # Update betting round
    updated_round = %{betting_round |
      players: updated_players,
      player_bets: Map.put(betting_round.player_bets, player_id, betting_round.current_bet),
      pot: betting_round.pot + call_amount,
      active_player_index: next_active_player_index(betting_round)
    }
    {:ok, updated_round}
  end

  defp execute_action(betting_round, player_id, {:raise, raise_amount}) do
    _player = Enum.find(betting_round.players, &(&1.id == player_id))
    current_bet_amount = betting_round.player_bets[player_id] || 0
    total_bet_amount = raise_amount - current_bet_amount
    
    # Update player chips
    updated_players = Enum.map(betting_round.players, fn p ->
      if p.id == player_id, do: %{p | chips: p.chips - total_bet_amount}, else: p
    end)
    
    # Update betting round
    updated_round = %{betting_round |
      players: updated_players,
      current_bet: raise_amount,
      player_bets: Map.put(betting_round.player_bets, player_id, raise_amount),
      pot: betting_round.pot + total_bet_amount,
      last_raise_size: raise_amount - betting_round.current_bet,
      active_player_index: next_active_player_index(betting_round)
    }
    {:ok, updated_round}
  end

  defp execute_action(betting_round, _player_id, {:check}) do
    updated_round = %{betting_round |
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
    
    # Update betting round
    updated_round = %{betting_round |
      players: updated_players,
      player_bets: Map.put(betting_round.player_bets, player_id, all_in_amount),
      pot: betting_round.pot + player.chips,
      all_in_players: MapSet.put(betting_round.all_in_players, player_id),
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
      # Check if all active players have the same bet amount
      active_player_ids = 
        betting_round.players
        |> Enum.map(& &1.id)
        |> Enum.reject(&(&1 in betting_round.folded_players))
      
      bet_amounts = 
        active_player_ids
        |> Enum.map(&(betting_round.player_bets[&1] || 0))
        |> Enum.uniq()
      
      # All active players have same bet amount
      length(bet_amounts) == 1
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

  defp create_side_pots(player_bets, all_in_players) do
    # Create side pots based on all-in amounts
    _all_in_amounts = 
      player_bets
      |> Enum.filter(fn {player_id, _} -> player_id in all_in_players end)
      |> Enum.map(&elem(&1, 1))
      |> Enum.uniq()
      |> Enum.sort()
    
    # Find minimum all-in amount
    min_all_in = 
      player_bets
      |> Enum.filter(fn {player_id, _} -> player_id in all_in_players end)
      |> Enum.map(&elem(&1, 1))
      |> Enum.min()
    
    # Create main pot up to min all-in amount
    main_pot_amount = min_all_in * length(player_bets)
    eligible_players = player_bets |> Enum.map(&elem(&1, 0)) |> MapSet.new()
    
    # Create side pot for remaining amount
    side_pot_players = 
      player_bets
      |> Enum.filter(fn {_, bet} -> bet > min_all_in end)
      |> Enum.map(&elem(&1, 0))
      |> MapSet.new()
    
    side_pot_amount = 
      player_bets
      |> Enum.filter(fn {_, bet} -> bet > min_all_in end)
      |> Enum.map(fn {_, bet} -> bet - min_all_in end)
      |> Enum.sum()
    
    pots = [%{amount: main_pot_amount, eligible_players: eligible_players}]
    
    if side_pot_amount > 0 do
      pots ++ [%{amount: side_pot_amount, eligible_players: side_pot_players}]
    else
      pots
    end
  end
end