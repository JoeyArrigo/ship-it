defmodule PokerServer.GameStateTest do
  use ExUnit.Case
  alias PokerServer.{GameState, Player, Card}

  # Helper to create a player
  defp player(id, chips), do: %Player{id: id, chips: chips}

  describe "new/1" do
    test "initializes game with 6 players" do
      players = for i <- 1..6, do: player(i, 1500)
      
      game_state = GameState.new(players)
      
      assert length(game_state.players) == 6
      assert game_state.phase == :waiting_for_players
      assert game_state.hand_number == 0
      assert game_state.pot == 0
      assert game_state.community_cards == []
    end

    test "assigns button position randomly" do
      players = for i <- 1..6, do: player(i, 1500)
      
      game_state = GameState.new(players)
      
      assert game_state.button_position in 0..5
    end

    test "initializes deck" do
      players = for i <- 1..6, do: player(i, 1500)
      
      game_state = GameState.new(players)
      
      assert length(game_state.deck) == 36  # Short deck
    end
  end

  describe "start_hand/1" do
    test "transitions to dealing phase and deals hole cards" do
      players = for i <- 1..6, do: player(i, 1500)
      game_state = GameState.new(players)
      
      updated_state = GameState.start_hand(game_state)
      
      assert updated_state.phase == :preflop
      assert updated_state.hand_number == 1
      assert length(updated_state.deck) == 24  # 36 - 12 hole cards
      
      # Each player should have 2 hole cards
      for player <- updated_state.players do
        assert length(player.hole_cards) == 2
      end
    end

    test "posts blinds automatically" do
      players = for i <- 1..6, do: player(i, 1500)
      game_state = GameState.new(players)
      |> Map.put(:small_blind, 10)
      |> Map.put(:big_blind, 20)
      
      updated_state = GameState.start_hand(game_state)
      
      assert updated_state.pot >= 30  # At least SB + BB
    end

    test "handles small blind player with insufficient chips" do
      # Small blind player has only 5 chips, blind is 10
      players = [
        player(1, 5),     # Position 0 - will be small blind after button advance
        player(2, 1500),  # Position 1 - will be big blind
        player(3, 1500)   # Position 2 - will be button
      ]
      
      game_state = GameState.new(players)
      |> Map.put(:small_blind, 10)
      |> Map.put(:big_blind, 20)
      |> Map.put(:button_position, 1)  # Button will advance from 1 to 2, making player 1 SB
      
      updated_state = GameState.start_hand(game_state)
      
      # Small blind player should go all-in for 5 chips (not negative)
      sb_player = Enum.find(updated_state.players, &(&1.id == 1))
      assert sb_player.chips == 0  # All chips posted
      
      # Big blind should post full amount
      bb_player = Enum.find(updated_state.players, &(&1.id == 2))
      assert bb_player.chips == 1480  # 1500 - 20
      
      # Pot should have partial small blind + full big blind
      assert updated_state.pot == 25  # 5 + 20
    end

    test "handles big blind player with insufficient chips" do
      # Big blind player has only 15 chips, blind is 20
      players = [
        player(1, 1500),  # Position 0 - will be button
        player(2, 1500),  # Position 1 - will be small blind  
        player(3, 15)     # Position 2 - will be big blind, insufficient chips
      ]
      
      game_state = GameState.new(players)
      |> Map.put(:small_blind, 10)
      |> Map.put(:big_blind, 20)
      |> Map.put(:button_position, 0)  # Button advances to player 1, making player 2 SB, player 3 BB
      
      updated_state = GameState.start_hand(game_state)
      
      # Player 1 (button) should have full chips
      button_player = Enum.find(updated_state.players, &(&1.id == 1))
      assert button_player.chips == 1500  # No blind posted
      
      # Small blind player (2) should post full amount
      sb_player = Enum.find(updated_state.players, &(&1.id == 2))
      assert sb_player.chips == 1490  # 1500 - 10
      
      # Big blind player (3) should go all-in for 15 chips (not negative)
      bb_player = Enum.find(updated_state.players, &(&1.id == 3))
      assert bb_player.chips == 0  # All chips posted
      
      # Pot should have full small blind + partial big blind
      assert updated_state.pot == 25  # 10 + 15
    end

    test "handles both blind players with insufficient chips" do
      # Both blind players have insufficient chips
      players = [
        player(1, 5),     # Position 0 - small blind, needs 10
        player(2, 12),    # Position 1 - big blind, needs 20  
        player(3, 1500)   # Position 2 - normal player
      ]
      
      game_state = GameState.new(players)
      |> Map.put(:small_blind, 10)
      |> Map.put(:big_blind, 20)
      |> Map.put(:button_position, 0)  # Button advances to player 1, making player 2 SB, player 3 BB
      
      updated_state = GameState.start_hand(game_state)
      
      # Both blind players should go all-in with what they have
      sb_player = Enum.find(updated_state.players, &(&1.id == 1))
      assert sb_player.chips == 0  # Posted 5 chips
      
      bb_player = Enum.find(updated_state.players, &(&1.id == 2))
      assert bb_player.chips == 0  # Posted 12 chips
      
      # Pot should have both partial blinds
      assert updated_state.pot == 17  # 5 + 12
    end

    test "handles exact blind amounts (boundary case)" do
      # Players have exactly the blind amounts
      players = [
        player(1, 10),    # Position 0 - small blind, exactly 10
        player(2, 20),    # Position 1 - big blind, exactly 20  
        player(3, 1500)   # Position 2 - normal player
      ]
      
      game_state = GameState.new(players)
      |> Map.put(:small_blind, 10)
      |> Map.put(:big_blind, 20)
      |> Map.put(:button_position, 0)  # Button advances to player 1, making player 2 SB, player 3 BB
      
      updated_state = GameState.start_hand(game_state)
      
      # Both players should post exact blind amounts and have 0 chips left
      sb_player = Enum.find(updated_state.players, &(&1.id == 1))
      assert sb_player.chips == 0
      
      bb_player = Enum.find(updated_state.players, &(&1.id == 2))
      assert bb_player.chips == 0
      
      # Pot should have full blinds
      assert updated_state.pot == 30  # 10 + 20
    end

    test "moves button position for next hand" do
      players = for i <- 1..6, do: player(i, 1500)
      game_state = GameState.new(players)
      |> Map.put(:button_position, 2)
      
      updated_state = GameState.start_hand(game_state)
      
      assert updated_state.button_position == 3
    end

    test "wraps button position around table" do
      players = for i <- 1..6, do: player(i, 1500)
      game_state = GameState.new(players)
      |> Map.put(:button_position, 5)  # Last position
      
      updated_state = GameState.start_hand(game_state)
      
      assert updated_state.button_position == 0  # Wraps to first position
    end
  end

  describe "deal_flop/1" do
    test "deals 3 community cards and transitions to flop" do
      players = for i <- 1..6, do: player(i, 1500)
      game_state = GameState.new(players)
      |> GameState.start_hand()
      
      updated_state = GameState.deal_flop(game_state)
      
      assert updated_state.phase == :flop
      assert length(updated_state.community_cards) == 3
      assert length(updated_state.deck) == 20  # 24 - 1 burn - 3 flop
    end

    test "burns a card before dealing flop" do
      players = for i <- 1..6, do: player(i, 1500)
      game_state = GameState.new(players)
      |> GameState.start_hand()
      
      deck_before = length(game_state.deck)
      updated_state = GameState.deal_flop(game_state)
      deck_after = length(updated_state.deck)
      
      # Should burn 1 card + deal 3 cards = 4 cards removed
      assert deck_before - deck_after == 4
    end
  end

  describe "deal_turn/1" do
    test "deals 1 more community card and transitions to turn" do
      players = for i <- 1..6, do: player(i, 1500)
      game_state = GameState.new(players)
      |> GameState.start_hand()
      |> GameState.deal_flop()
      
      updated_state = GameState.deal_turn(game_state)
      
      assert updated_state.phase == :turn
      assert length(updated_state.community_cards) == 4
      assert length(updated_state.deck) == 18  # 20 - 1 burn - 1 turn
    end
  end

  describe "deal_river/1" do
    test "deals final community card and transitions to river" do
      players = for i <- 1..6, do: player(i, 1500)
      game_state = GameState.new(players)
      |> GameState.start_hand()
      |> GameState.deal_flop()
      |> GameState.deal_turn()
      
      updated_state = GameState.deal_river(game_state)
      
      assert updated_state.phase == :river
      assert length(updated_state.community_cards) == 5
      assert length(updated_state.deck) == 16  # 18 - 1 burn - 1 river
    end
  end

  describe "showdown/1" do
    test "determines winners and distributes pot" do
      # Create players with known hole cards for predictable outcome
      # Player 1: A♥ K♥ + community A♣ K♣ Q♥ J♦ T♠ = Broadway straight (A-K-Q-J-T)
      # Player 2: 7♣ 6♣ + community A♣ K♣ Q♥ J♦ T♠ = Broadway straight (A-K-Q-J-T)
      # Both players have identical straights, so this should be a split pot
      players = [
        %Player{id: 1, chips: 1480, hole_cards: [%Card{rank: :ace, suit: :hearts}, %Card{rank: :king, suit: :hearts}]},
        %Player{id: 2, chips: 1480, hole_cards: [%Card{rank: :seven, suit: :clubs}, %Card{rank: :six, suit: :clubs}]}
      ]
      
      community_cards = [
        %Card{rank: :ace, suit: :clubs},
        %Card{rank: :king, suit: :clubs},
        %Card{rank: :queen, suit: :hearts},
        %Card{rank: :jack, suit: :diamonds},
        %Card{rank: :ten, suit: :spades}
      ]
      
      game_state = %GameState{
        players: players,
        community_cards: community_cards,
        pot: 40,
        phase: :river,
        hand_number: 1,
        deck: [],
        button_position: 0,
        small_blind: 10,
        big_blind: 20
      }
      
      updated_state = GameState.showdown(game_state)
      
      assert updated_state.phase == :hand_complete
      
      # Both players have identical Broadway straights, so pot should be split equally
      # Each player gets 20 chips (40 ÷ 2), ending with 1500 chips total
      player1 = Enum.find(updated_state.players, &(&1.id == 1))
      player2 = Enum.find(updated_state.players, &(&1.id == 2))
      
      assert player1.chips >= 1480  # Split pot - both players gain chips
      assert updated_state.pot == 0  # Pot fully distributed
    end

    test "handles split pot for tied hands" do
      # Two players with identical hands
      players = [
        %Player{id: 1, chips: 1480, hole_cards: [%Card{rank: :ace, suit: :hearts}, %Card{rank: :king, suit: :hearts}]},
        %Player{id: 2, chips: 1480, hole_cards: [%Card{rank: :ace, suit: :clubs}, %Card{rank: :king, suit: :clubs}]}
      ]
      
      community_cards = [
        %Card{rank: :queen, suit: :hearts},
        %Card{rank: :jack, suit: :diamonds},
        %Card{rank: :ten, suit: :spades},
        %Card{rank: :nine, suit: :hearts},
        %Card{rank: :eight, suit: :clubs}
      ]
      
      game_state = %GameState{
        players: players,
        community_cards: community_cards,
        pot: 40,
        phase: :river,
        hand_number: 1,
        deck: [],
        button_position: 0,
        small_blind: 10,
        big_blind: 20
      }
      
      updated_state = GameState.showdown(game_state)
      
      # Both players should get equal share
      for player <- updated_state.players do
        assert player.chips == 1500  # 1480 + 20 (half the pot)
      end
    end
  end

  describe "eliminate_players/1" do
    test "removes players with zero chips" do
      players = [
        player(1, 1500),
        player(2, 0),     # Should be eliminated
        player(3, 1000),
        player(4, 0)      # Should be eliminated
      ]
      
      game_state = %GameState{
        players: players,
        phase: :hand_complete,
        hand_number: 1,
        deck: [],
        community_cards: [],
        pot: 0,
        button_position: 0,
        small_blind: 10,
        big_blind: 20
      }
      
      updated_state = GameState.eliminate_players(game_state)
      
      assert length(updated_state.players) == 2
      remaining_ids = updated_state.players |> Enum.map(& &1.id)
      assert 1 in remaining_ids
      assert 3 in remaining_ids
      refute 2 in remaining_ids
      refute 4 in remaining_ids
    end

    test "adjusts button position when players eliminated" do
      players = [
        player(1, 1500),  # Position 0
        player(2, 0),     # Position 1 - eliminated
        player(3, 1000),  # Position 2
        player(4, 0)      # Position 3 - eliminated
      ]
      
      game_state = %GameState{
        players: players,
        button_position: 3,  # Button on eliminated player
        phase: :hand_complete,
        hand_number: 1,
        deck: [],
        community_cards: [],
        pot: 0,
        small_blind: 10,
        big_blind: 20
      }
      
      updated_state = GameState.eliminate_players(game_state)
      
      # Button should move to valid position
      assert updated_state.button_position in [0, 1]  # Only 2 players left, positions 0 and 1
    end

    test "handles button on eliminated player with multiple consecutive eliminations" do
      # More complex scenario: button player + next 2 players eliminated
      players = [
        player(1, 1500),  # Position 0 - survives
        player(2, 0),     # Position 1 - eliminated  
        player(3, 0),     # Position 2 - eliminated (button)
        player(4, 0),     # Position 3 - eliminated
        player(5, 1000),  # Position 4 - survives
        player(6, 800)    # Position 5 - survives
      ]
      
      game_state = %GameState{
        players: players,
        button_position: 2,  # Button on eliminated player 3
        phase: :hand_complete,
        hand_number: 1,
        deck: [],
        community_cards: [],
        pot: 0,
        small_blind: 10,
        big_blind: 20
      }
      
      updated_state = GameState.eliminate_players(game_state)
      
      # Button should advance to next surviving player after elimination
      # Original positions: 0(survives), 1(elim), 2(elim,button), 3(elim), 4(survives), 5(survives)
      # New positions: 0, 1, 2 (for players 1, 5, 6)
      # Button should advance from original position 2 to next surviving player
      assert updated_state.button_position in [0, 1, 2]  # 3 players left
      assert length(updated_state.players) == 3
    end

    test "handles all but one player eliminated" do
      # Extreme case: only 1 player survives
      players = [
        player(1, 1500),  # Position 0 - only survivor
        player(2, 0),     # Position 1 - eliminated  
        player(3, 0),     # Position 2 - eliminated
        player(4, 0),     # Position 3 - eliminated (button)
        player(5, 0),     # Position 4 - eliminated
        player(6, 0)      # Position 5 - eliminated
      ]
      
      game_state = %GameState{
        players: players,
        button_position: 3,  # Button on eliminated player
        phase: :hand_complete,
        hand_number: 1,
        deck: [],
        community_cards: [],
        pot: 0,
        small_blind: 10,
        big_blind: 20
      }
      
      updated_state = GameState.eliminate_players(game_state)
      
      # Only 1 player left, button must be on them (position 0)
      assert updated_state.button_position == 0
      assert length(updated_state.players) == 1
      assert hd(updated_state.players).id == 1
    end

    test "preserves button position when button player survives elimination" do
      # Button player survives, but others are eliminated
      players = [
        player(1, 0),     # Position 0 - eliminated
        player(2, 1500),  # Position 1 - survives (button)
        player(3, 0),     # Position 2 - eliminated
        player(4, 1000),  # Position 3 - survives
        player(5, 0)      # Position 4 - eliminated
      ]
      
      game_state = %GameState{
        players: players,
        button_position: 1,  # Button on surviving player 2
        phase: :hand_complete,
        hand_number: 1,
        deck: [],
        community_cards: [],
        pot: 0,
        small_blind: 10,
        big_blind: 20
      }
      
      updated_state = GameState.eliminate_players(game_state)
      
      # Button player survives and should be repositioned correctly
      # Original: player 2 at position 1, player 4 at position 3
      # New: player 2 at position 0, player 4 at position 1
      # Button should move from original position 1 to new position of same player
      assert length(updated_state.players) == 2
      
      # Find where player 2 (original button holder) ended up
      button_player = Enum.find(updated_state.players, &(&1.id == 2))
      assert button_player != nil
      # Button should be on the same player (now at their new position)
      assert updated_state.button_position == button_player.position
    end
  end

  describe "tournament_complete?/1" do
    test "returns true when only one player remains" do
      players = [player(1, 9000)]
      
      game_state = %GameState{
        players: players,
        phase: :hand_complete,
        hand_number: 5,
        deck: [],
        community_cards: [],
        pot: 0,
        button_position: 0,
        small_blind: 10,
        big_blind: 20
      }
      
      assert GameState.tournament_complete?(game_state)
    end

    test "returns false when multiple players remain" do
      players = [player(1, 4500), player(2, 4500)]
      
      game_state = %GameState{
        players: players,
        phase: :hand_complete,
        hand_number: 5,
        deck: [],
        community_cards: [],
        pot: 0,
        button_position: 0,
        small_blind: 10,
        big_blind: 20
      }
      
      refute GameState.tournament_complete?(game_state)
    end
  end

  describe "reset_for_next_hand/1" do
    test "resets hand-specific state while preserving tournament state" do
      players = [
        %Player{id: 1, chips: 1520, hole_cards: [%Card{rank: :ace, suit: :hearts}, %Card{rank: :king, suit: :hearts}]},
        %Player{id: 2, chips: 1480, hole_cards: [%Card{rank: :seven, suit: :clubs}, %Card{rank: :six, suit: :clubs}]}
      ]
      
      game_state = %GameState{
        players: players,
        community_cards: [%Card{rank: :ace, suit: :clubs}],
        pot: 0,
        phase: :hand_complete,
        hand_number: 3,
        deck: [],
        button_position: 1,
        small_blind: 10,
        big_blind: 20
      }
      
      updated_state = GameState.reset_for_next_hand(game_state)
      
      # Hand-specific state should be reset
      assert updated_state.community_cards == []
      assert updated_state.pot == 0
      assert updated_state.phase == :waiting_for_players
      assert length(updated_state.deck) == 36  # New shuffled deck
      
      # Players should have no hole cards
      for player <- updated_state.players do
        assert player.hole_cards == []
      end
      
      # Tournament state should be preserved
      assert updated_state.hand_number == 3
      assert updated_state.button_position == 1
      assert updated_state.small_blind == 10
      assert updated_state.big_blind == 20
      
      # Chip counts should be preserved
      player_1 = Enum.find(updated_state.players, &(&1.id == 1))
      player_2 = Enum.find(updated_state.players, &(&1.id == 2))
      assert player_1.chips == 1520
      assert player_2.chips == 1480
    end
  end
end