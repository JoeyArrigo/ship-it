defmodule PokerServer.Player do
  defstruct [:id, :chips, :position, hole_cards: []]
end