defmodule PokerServer.GameState.PublicState do
  @moduledoc """
  Public game state that can be safely stored in snapshots and shared.
  
  Contains all game information that is visible to all players and observers:
  - Player positions, chips, and public actions
  - Community cards (once revealed)
  - Pot sizes and betting information
  - Game phase and hand number
  - Blinds and button position
  
  This state excludes any sensitive card information (hole cards, deck state).
  """
  
  alias PokerServer.{Card, Types}
  alias PokerServer.Player.PublicPlayer
  
  @derive Jason.Encoder
  @type t :: %__MODULE__{
    players: [PublicPlayer.t()],
    community_cards: [Card.t()],
    pot: non_neg_integer(),
    phase: Types.game_state_phase(),
    hand_number: non_neg_integer(),
    button_position: non_neg_integer(),
    small_blind: non_neg_integer(),
    big_blind: non_neg_integer()
  }
  
  defstruct [
    :players,
    :community_cards,
    :pot,
    :phase,
    :hand_number,
    :button_position,
    :small_blind,
    :big_blind
  ]
  
  @doc """
  Creates public state from a full GameState by stripping sensitive information.
  """
  @spec from_game_state(PokerServer.GameState.t()) :: t()
  def from_game_state(game_state) do
    %__MODULE__{
      players: Enum.map(game_state.players, &PublicPlayer.from_player/1),
      community_cards: game_state.community_cards,
      pot: game_state.pot,
      phase: game_state.phase,
      hand_number: game_state.hand_number,
      button_position: game_state.button_position,
      small_blind: game_state.small_blind,
      big_blind: game_state.big_blind
    }
  end
  
  @doc """
  Validates that this public state contains no sensitive card information.
  """
  @spec validate_security(t()) :: :ok | {:error, term()}
  def validate_security(public_state) do
    # Verify no players have hole cards
    players_with_cards = Enum.filter(public_state.players, fn player ->
      length(player.hole_cards) > 0
    end)
    
    if length(players_with_cards) > 0 do
      {:error, {:security_violation, "Public state contains player hole cards"}}
    else
      :ok
    end
  end
end