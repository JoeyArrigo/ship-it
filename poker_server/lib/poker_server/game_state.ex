defmodule PokerServer.GameState do
  defstruct [:players, :community_cards, :pot, :phase, :hand_number, :deck, :button_position, :small_blind, :big_blind]
end