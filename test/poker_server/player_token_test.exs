defmodule PokerServer.PlayerTokenTest do
  use ExUnit.Case
  alias PokerServer.PlayerToken

  describe "PlayerToken" do
    test "generates and validates tokens correctly" do
      game_id = "game123"
      player_name = "Alice"

      # Generate a token
      token = PlayerToken.generate_token(game_id, player_name)
      assert is_binary(token)

      # Validate the token
      assert {:ok, ^player_name} = PlayerToken.validate_token(token, game_id)
    end

    test "rejects tokens with mismatched game_id" do
      game_id = "game123"
      different_game_id = "game456"
      player_name = "Alice"

      token = PlayerToken.generate_token(game_id, player_name)

      # Should fail when game_id doesn't match
      assert {:error, :game_id_mismatch} = PlayerToken.validate_token(token, different_game_id)
    end

    test "rejects invalid tokens" do
      game_id = "game123"
      invalid_token = "invalid_token"

      assert {:error, _reason} = PlayerToken.validate_token(invalid_token, game_id)
    end

    test "decodes tokens without game_id validation" do
      game_id = "game123"
      player_name = "Alice"

      token = PlayerToken.generate_token(game_id, player_name)

      assert {:ok, {^game_id, ^player_name}} = PlayerToken.decode_token(token)
    end

    test "handles empty or nil inputs gracefully" do
      # Should handle gracefully without crashing
      assert {:error, _reason} = PlayerToken.validate_token(nil, "game123")
      assert {:error, _reason} = PlayerToken.validate_token("", "game123")
      assert {:error, _reason} = PlayerToken.decode_token(nil)
    end
  end
end