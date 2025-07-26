defmodule PokerServer.BettingRound do
  defstruct [:players, :small_blind, :big_blind, :round_type, :pot, :current_bet, :player_bets, :active_player_index, :folded_players, :all_in_players]
end