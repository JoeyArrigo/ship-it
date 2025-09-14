defmodule PokerServer.Card do
  @type rank :: :ace | 6..10 | :jack | :queen | :king
  @type suit :: :hearts | :diamonds | :clubs | :spades

  @derive Jason.Encoder
  @type t :: %__MODULE__{
          rank: rank(),
          suit: suit()
        }

  defstruct [:rank, :suit]
end
