defmodule PokerServer.GameState.SecureStateTest do
  use ExUnit.Case, async: true
  
  alias PokerServer.GameState.{SecureState, PublicState, PrivateState}
  alias PokerServer.{GameState, Player, Card}
  
  describe "SecureState" do
    setup do
      # Create test players with hole cards
      players = [
        %Player{id: "player1", chips: 1000, position: 0, hole_cards: [
          %Card{rank: :ace, suit: :spades},
          %Card{rank: :king, suit: :hearts}
        ]},
        %Player{id: "player2", chips: 1500, position: 1, hole_cards: [
          %Card{rank: :queen, suit: :diamonds},
          %Card{rank: :jack, suit: :clubs}
        ]}
      ]
      
      # Create a test game state
      game_state = %GameState{
        players: players,
        community_cards: [%Card{rank: :ten, suit: :spades}],
        pot: 150,
        phase: :flop,
        hand_number: 5,
        deck: [%Card{rank: :nine, suit: :hearts}],  # Minimal deck for testing
        button_position: 0,
        small_blind: 25,
        big_blind: 50
      }
      
      %{game_state: game_state, players: players}
    end
    
    test "separates public and private state correctly", %{game_state: game_state} do
      secure_state = SecureState.from_game_state(game_state)
      
      # Verify public state has no sensitive card information
      public_state = SecureState.public_only(secure_state)
      
      assert public_state.pot == 150
      assert public_state.phase == :flop
      assert public_state.hand_number == 5
      assert length(public_state.community_cards) == 1
      
      # Verify players have no hole cards in public state
      Enum.each(public_state.players, fn player ->
        assert player.hole_cards == []
        assert player.chips > 0  # But other data is preserved
      end)
      
      # Verify private state contains sensitive information
      assert secure_state.private != nil
      assert length(secure_state.private.deck) == 1
      assert map_size(secure_state.private.player_hole_cards) == 2
    end
    
    test "reconstructs complete game state from public and private", %{game_state: original_game_state} do
      secure_state = SecureState.from_game_state(original_game_state)
      
      # Reconstruct should give us back the original state
      case SecureState.to_game_state(secure_state) do
        {:ok, reconstructed_state} ->
          assert reconstructed_state.pot == original_game_state.pot
          assert reconstructed_state.phase == original_game_state.phase
          assert reconstructed_state.hand_number == original_game_state.hand_number
          assert length(reconstructed_state.community_cards) == length(original_game_state.community_cards)
          assert length(reconstructed_state.deck) == length(original_game_state.deck)
          
          # Verify players have their hole cards restored
          reconstructed_player1 = Enum.find(reconstructed_state.players, &(&1.id == "player1"))
          original_player1 = Enum.find(original_game_state.players, &(&1.id == "player1"))
          
          assert length(reconstructed_player1.hole_cards) == 2
          assert reconstructed_player1.hole_cards == original_player1.hole_cards
          
        {:error, reason} ->
          flunk("Failed to reconstruct game state: #{inspect(reason)}")
      end
    end
    
    test "fails to reconstruct without private state" do
      public_state = %PublicState{
        players: [],
        community_cards: [],
        pot: 0,
        phase: :waiting_for_players,
        hand_number: 0,
        button_position: 0,
        small_blind: 25,
        big_blind: 50
      }
      
      secure_state_without_private = SecureState.from_public_state(public_state)
      
      case SecureState.to_game_state(secure_state_without_private) do
        {:error, reason} ->
          assert reason == "Cannot reconstruct GameState without private state"
        {:ok, _} ->
          flunk("Should have failed without private state")
      end
    end
    
    test "validates security of public state" do
      # Create a public state with hole cards (security violation)
      unsafe_public_state = %PublicState{
        players: [%PokerServer.Player.PublicPlayer{
          id: "player1", 
          chips: 1000, 
          position: 0, 
          hole_cards: [%Card{rank: :ace, suit: :spades}]  # This should not be here!
        }],
        community_cards: [],
        pot: 0,
        phase: :waiting_for_players,
        hand_number: 0,
        button_position: 0,
        small_blind: 25,
        big_blind: 50
      }
      
      case PublicState.validate_security(unsafe_public_state) do
        {:error, {:security_violation, _message}} ->
          # This is expected - we detected the security violation
          :ok
        :ok ->
          flunk("Should have detected security violation")
      end
    end
  end
end