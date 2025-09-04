defmodule PokerServer.Tournament.SecureSnapshotTest do
  use ExUnit.Case, async: true
  
  alias PokerServer.Tournament.Snapshot
  alias PokerServer.GameState.{SecureState, PublicState}
  alias PokerServer.{GameState, Player, Card}
  
  describe "Secure Snapshot Creation" do
    test "extracts only public state from GameState" do
      # Create a game state with sensitive card information
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
      
      game_state = %GameState{
        players: players,
        community_cards: [%Card{rank: :ten, suit: :spades}],
        pot: 150,
        phase: :flop,
        hand_number: 5,
        deck: [%Card{rank: :nine, suit: :hearts}],  # This should NOT be in snapshot
        button_position: 0,
        small_blind: 25,
        big_blind: 50
      }
      
      # Test that extract_public_state removes sensitive information
      public_state = Snapshot.send(:extract_public_state, [game_state])
      
      # Verify public state structure
      assert public_state.pot == 150
      assert public_state.phase == :flop
      assert public_state.hand_number == 5
      assert length(public_state.community_cards) == 1
      
      # Verify no sensitive card data
      Enum.each(public_state.players, fn player ->
        assert player.hole_cards == []
      end)
      
      # The deck should not be present in public state (it's not even a field)
      refute Map.has_key?(public_state, :deck)
    end
    
    test "handles SecureState input correctly" do
      players = [
        %Player{id: "player1", chips: 1000, position: 0, hole_cards: [
          %Card{rank: :ace, suit: :spades}
        ]}
      ]
      
      game_state = %GameState{
        players: players,
        community_cards: [],
        pot: 0,
        phase: :waiting_for_players,
        hand_number: 0,
        deck: [%Card{rank: :king, suit: :hearts}],
        button_position: 0,
        small_blind: 25,
        big_blind: 50
      }
      
      secure_state = SecureState.from_game_state(game_state)
      
      # Should extract public state from SecureState
      public_state = Snapshot.send(:extract_public_state, [secure_state])
      
      assert public_state.pot == 0
      assert public_state.phase == :waiting_for_players
      
      # No sensitive data should be present
      Enum.each(public_state.players, fn player ->
        assert player.hole_cards == []
      end)
    end
    
    test "rejects unknown state formats" do
      unknown_state = %{some: "random", data: "structure"}
      
      assert_raise ArgumentError, ~r/Cannot extract public state/, fn ->
        Snapshot.send(:extract_public_state, [unknown_state])
      end
    end
    
    test "handles server state format" do
      game_state = %GameState{
        players: [%Player{id: "player1", chips: 1000, position: 0, hole_cards: [
          %Card{rank: :ace, suit: :spades}
        ]}],
        community_cards: [],
        pot: 0,
        phase: :waiting_for_players,
        hand_number: 0,
        deck: [%Card{rank: :king, suit: :hearts}],
        button_position: 0,
        small_blind: 25,
        big_blind: 50
      }
      
      # This is the format that GameServer.get_state returns
      server_state = %{
        game_id: "test_game",
        game_state: game_state,
        betting_round: nil,
        phase: :waiting_to_start
      }
      
      public_state = Snapshot.send(:extract_public_state, [server_state])
      
      assert public_state.pot == 0
      assert public_state.phase == :waiting_for_players
      
      # Verify card data was stripped
      [player] = public_state.players
      assert player.hole_cards == []
    end
  end
end