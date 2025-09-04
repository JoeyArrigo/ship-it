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
    big_blind: non_neg_integer(),
    # Betting context for complete recovery
    active_player_id: String.t() | nil,
    current_bet: non_neg_integer(),
    betting_round_type: atom() | nil,
    folded_players: [String.t()],
    all_in_players: [String.t()],
    player_bets: %{String.t() => non_neg_integer()}
  }
  
  defstruct [
    :players,
    :community_cards,
    :pot,
    :phase,
    :hand_number,
    :button_position,
    :small_blind,
    :big_blind,
    :active_player_id,
    :current_bet,
    :betting_round_type,
    :folded_players,
    :all_in_players,
    :player_bets
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
      big_blind: game_state.big_blind,
      # No betting context available from just game state
      active_player_id: nil,
      current_bet: 0,
      betting_round_type: nil,
      folded_players: [],
      all_in_players: [],
      player_bets: %{}
    }
  end
  
  @doc """
  Creates public state from complete server state including betting context.
  This enables complete recovery without event replay.
  """
  @spec from_server_state(map()) :: t()
  def from_server_state(server_state) do
    betting_round = server_state[:betting_round]
    
    # Extract betting context if betting round exists
    {active_player_id, current_bet, betting_round_type, folded_players, all_in_players, player_bets} = 
      if betting_round do
        active_player = if betting_round.active_player_index do
          Enum.at(betting_round.players, betting_round.active_player_index)
        end
        
        {
          active_player && active_player.id,
          betting_round.current_bet || 0,
          betting_round.round_type,
          MapSet.to_list(betting_round.folded_players || MapSet.new()),
          MapSet.to_list(betting_round.all_in_players || MapSet.new()),
          betting_round.player_bets || %{}
        }
      else
        {nil, 0, nil, [], [], %{}}
      end
    
    %__MODULE__{
      players: Enum.map(server_state.game_state.players, &PublicPlayer.from_player/1),
      community_cards: server_state.game_state.community_cards,
      pot: server_state.game_state.pot,
      phase: server_state.game_state.phase,
      hand_number: server_state.game_state.hand_number,
      button_position: server_state.game_state.button_position,
      small_blind: server_state.game_state.small_blind,
      big_blind: server_state.game_state.big_blind,
      # Complete betting context for recovery
      active_player_id: active_player_id,
      current_bet: current_bet,
      betting_round_type: betting_round_type,
      folded_players: folded_players,
      all_in_players: all_in_players,
      player_bets: player_bets
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