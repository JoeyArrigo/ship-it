defmodule PokerServer.InputValidatorTest do
  use ExUnit.Case
  alias PokerServer.{InputValidator, Player}

  describe "validate_players/1" do
    test "accepts valid player list" do
      players = [{"player1", 1500}, {"player2", 1000}, {"player3", 2000}]
      assert {:ok, ^players} = InputValidator.validate_players(players)
    end

    test "rejects empty player list" do
      assert {:error, :empty_player_list} = InputValidator.validate_players([])
    end

    test "rejects too many players" do
      players = for i <- 1..15, do: {"player#{i}", 1000}
      assert {:error, :too_many_players} = InputValidator.validate_players(players)
    end

    test "rejects insufficient players" do
      players = [{"player1", 1500}]
      assert {:error, :insufficient_players} = InputValidator.validate_players(players)
    end

    test "rejects duplicate player IDs" do
      players = [{"player1", 1500}, {"player1", 1000}, {"player3", 2000}]
      assert {:error, :duplicate_player_ids} = InputValidator.validate_players(players)
    end

    test "rejects invalid player list format" do
      assert {:error, :invalid_player_list_format} = InputValidator.validate_players("not a list")
      assert {:error, :invalid_player_list_format} = InputValidator.validate_players(nil)
    end

    test "rejects invalid player tuples" do
      players = [{"player1", 1500}, :invalid_tuple, {"player3", 2000}]

      assert {:error, {:invalid_player, :invalid_tuple}} =
               InputValidator.validate_players(players)
    end
  end

  describe "validate_player_id/1" do
    test "accepts valid string IDs" do
      assert :ok = InputValidator.validate_player_id("player1")
      assert :ok = InputValidator.validate_player_id("user_123")
    end

    test "accepts valid integer IDs" do
      assert :ok = InputValidator.validate_player_id(123)
      assert :ok = InputValidator.validate_player_id(1)
    end

    test "accepts valid atom IDs" do
      assert :ok = InputValidator.validate_player_id(:player1)
      assert :ok = InputValidator.validate_player_id(:user)
    end

    test "rejects nil player ID" do
      assert {:error, :nil_player_id} = InputValidator.validate_player_id(nil)
    end

    test "rejects empty string ID" do
      assert {:error, :empty_player_id} = InputValidator.validate_player_id("")
    end

    test "rejects invalid types" do
      assert {:error, :invalid_player_id_type} = InputValidator.validate_player_id([])
      assert {:error, :invalid_player_id_type} = InputValidator.validate_player_id(%{})
      assert {:error, :invalid_player_id_type} = InputValidator.validate_player_id(1.5)
    end
  end

  describe "validate_chip_amount/1" do
    test "accepts positive integer chip amounts" do
      assert :ok = InputValidator.validate_chip_amount(1)
      assert :ok = InputValidator.validate_chip_amount(1500)
      assert :ok = InputValidator.validate_chip_amount(100_000)
    end

    test "rejects zero chips" do
      assert {:error, :non_positive_chips} = InputValidator.validate_chip_amount(0)
    end

    test "rejects negative chips" do
      assert {:error, :non_positive_chips} = InputValidator.validate_chip_amount(-100)
      assert {:error, :non_positive_chips} = InputValidator.validate_chip_amount(-1)
    end

    test "rejects excessively large chip amounts" do
      assert {:error, :chips_too_large} = InputValidator.validate_chip_amount(10_000_000)
    end

    test "rejects nil chip amount" do
      assert {:error, :nil_chip_amount} = InputValidator.validate_chip_amount(nil)
    end

    test "rejects invalid chip types" do
      assert {:error, :invalid_chip_type} = InputValidator.validate_chip_amount("1500")
      assert {:error, :invalid_chip_type} = InputValidator.validate_chip_amount(15.5)
      assert {:error, :invalid_chip_type} = InputValidator.validate_chip_amount([])
    end
  end

  describe "validate_action/1" do
    test "accepts valid basic actions" do
      assert :ok = InputValidator.validate_action({:fold})
      assert :ok = InputValidator.validate_action({:call})
      assert :ok = InputValidator.validate_action({:check})
      assert :ok = InputValidator.validate_action({:all_in})
    end

    test "accepts valid raise actions" do
      assert :ok = InputValidator.validate_action({:raise, 100})
      assert :ok = InputValidator.validate_action({:raise, 1})
      assert :ok = InputValidator.validate_action({:raise, 10_000})
    end

    test "rejects invalid raise amounts" do
      assert {:error, :invalid_raise_amount} = InputValidator.validate_action({:raise, 0})
      assert {:error, :invalid_raise_amount} = InputValidator.validate_action({:raise, -100})
    end

    test "rejects invalid raise types" do
      assert {:error, :invalid_raise_type} = InputValidator.validate_action({:raise, "100"})
      assert {:error, :invalid_raise_type} = InputValidator.validate_action({:raise, nil})
    end

    test "rejects unknown actions" do
      assert {:error, :unknown_action} = InputValidator.validate_action({:bet, 100})
      assert {:error, :unknown_action} = InputValidator.validate_action({:invalid})
    end

    test "rejects invalid action formats" do
      assert {:error, :invalid_action_format} = InputValidator.validate_action("fold")
      assert {:error, :invalid_action_format} = InputValidator.validate_action(nil)
      assert {:error, :invalid_action_format} = InputValidator.validate_action(123)
    end
  end

  describe "validate_player_exists/2" do
    setup do
      players = [
        %Player{id: "player1", chips: 1500, position: 0},
        %Player{id: "player2", chips: 1000, position: 1},
        %Player{id: :player3, chips: 2000, position: 2}
      ]

      {:ok, players: players}
    end

    test "accepts existing player IDs", %{players: players} do
      assert :ok = InputValidator.validate_player_exists("player1", players)
      assert :ok = InputValidator.validate_player_exists("player2", players)
      assert :ok = InputValidator.validate_player_exists(:player3, players)
    end

    test "rejects non-existent player IDs", %{players: players} do
      assert {:error, :player_not_found} =
               InputValidator.validate_player_exists("nonexistent", players)

      assert {:error, :player_not_found} = InputValidator.validate_player_exists(999, players)
    end

    test "rejects invalid players list" do
      assert {:error, :invalid_players_list} =
               InputValidator.validate_player_exists("player1", "not a list")

      assert {:error, :invalid_players_list} =
               InputValidator.validate_player_exists("player1", nil)
    end
  end

  describe "validate_position/2" do
    test "accepts valid positions" do
      assert :ok = InputValidator.validate_position(0, 6)
      assert :ok = InputValidator.validate_position(3, 6)
      assert :ok = InputValidator.validate_position(5, 6)
    end

    test "rejects out-of-bounds positions" do
      assert {:error, :position_out_of_bounds} = InputValidator.validate_position(-1, 6)
      assert {:error, :position_out_of_bounds} = InputValidator.validate_position(6, 6)
      assert {:error, :position_out_of_bounds} = InputValidator.validate_position(100, 6)
    end

    test "rejects invalid position types" do
      assert {:error, :invalid_position_type} = InputValidator.validate_position("0", 6)
      assert {:error, :invalid_position_type} = InputValidator.validate_position(nil, 6)
      assert {:error, :invalid_position_type} = InputValidator.validate_position(1.5, 6)
    end
  end

  describe "validate_game_state/1" do
    test "accepts valid game state with players" do
      game_state = %{players: [%Player{id: 1, chips: 1500}]}
      assert :ok = InputValidator.validate_game_state(game_state)
    end

    test "rejects game state with no players" do
      game_state = %{players: []}
      assert {:error, :no_players_in_game} = InputValidator.validate_game_state(game_state)
    end

    test "rejects corrupted players list" do
      game_state = %{players: "not a list"}
      assert {:error, :corrupted_players_list} = InputValidator.validate_game_state(game_state)
    end

    test "rejects invalid game state" do
      assert {:error, :invalid_game_state} = InputValidator.validate_game_state(nil)
      assert {:error, :invalid_game_state} = InputValidator.validate_game_state("not a map")
    end
  end
end
