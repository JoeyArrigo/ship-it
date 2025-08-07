defmodule PokerServer.Player do
  alias PokerServer.Card

  @type t :: %__MODULE__{
          id: String.t(),
          chips: non_neg_integer(),
          position: non_neg_integer() | nil,
          hole_cards: [Card.t()]
        }

  defstruct [:id, :chips, :position, hole_cards: []]
end
