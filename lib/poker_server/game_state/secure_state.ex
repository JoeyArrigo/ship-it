defmodule PokerServer.GameState.SecureState do
  @moduledoc """
  Secure wrapper for game state that properly separates public and private information.
  
  This replaces the monolithic GameState for snapshot and recovery purposes.
  It ensures that sensitive card information is never accidentally stored in snapshots.
  """
  
  alias PokerServer.GameState.{PublicState, PrivateState}
  alias PokerServer.GameState
  
  @type t :: %__MODULE__{
    public: PublicState.t(),
    private: PrivateState.t() | nil  # nil when reconstructed from snapshot
  }
  
  defstruct [:public, :private]
  
  @doc """
  Creates secure state from a traditional GameState.
  """
  @spec from_game_state(GameState.t()) :: t()
  def from_game_state(game_state) do
    %__MODULE__{
      public: PublicState.from_game_state(game_state),
      private: PrivateState.from_game_state(game_state)
    }
  end
  
  @doc """
  Reconstructs a complete GameState from public and private components.
  Requires both public state and private state to be present.
  """
  @spec to_game_state(t()) :: {:ok, GameState.t()} | {:error, term()}
  def to_game_state(%__MODULE__{public: _public, private: nil}) do
    {:error, "Cannot reconstruct GameState without private state"}
  end
  
  def to_game_state(%__MODULE__{public: public, private: private}) do
    # Merge public player data with private hole cards
    players = merge_player_data(public.players, private.player_hole_cards)
    
    game_state = %GameState{
      players: players,
      community_cards: public.community_cards,
      pot: public.pot,
      phase: public.phase,
      hand_number: public.hand_number,
      deck: private.deck,
      button_position: public.button_position,
      small_blind: public.small_blind,
      big_blind: public.big_blind
    }
    
    {:ok, game_state}
  end
  
  @doc """
  Returns only the public state for safe snapshot storage.
  """
  @spec public_only(t()) :: PublicState.t()
  def public_only(%__MODULE__{public: public}), do: public
  
  @doc """
  Adds private state to a secure state (used during recovery).
  """
  @spec with_private_state(t(), PrivateState.t()) :: t()
  def with_private_state(%__MODULE__{public: public}, private) do
    %__MODULE__{public: public, private: private}
  end
  
  @doc """
  Creates secure state from public state only (used when loading from snapshot).
  """
  @spec from_public_state(PublicState.t()) :: t()
  def from_public_state(public) do
    %__MODULE__{public: public, private: nil}
  end
  
  @doc """
  Validates that the secure state maintains proper security boundaries.
  """
  @spec validate_security(t()) :: :ok | {:error, term()}
  def validate_security(%__MODULE__{public: public, private: private}) do
    with :ok <- PublicState.validate_security(public),
         :ok <- validate_private_security(private) do
      :ok
    end
  end
  
  # Private helper functions
  
  defp merge_player_data(public_players, player_hole_cards) do
    Enum.map(public_players, fn public_player ->
      hole_cards = Map.get(player_hole_cards, public_player.id, [])
      PokerServer.Player.PublicPlayer.to_player(public_player, hole_cards)
    end)
  end
  
  defp validate_private_security(nil), do: :ok
  defp validate_private_security(private), do: PrivateState.validate_security(private)
end