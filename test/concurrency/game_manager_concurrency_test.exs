defmodule PokerServer.GameManagerConcurrencyTest do
  use ExUnit.Case
  alias PokerServer.GameManager

  # Helper to create a player tuple (format expected by GameServer)
  defp player(id, chips), do: {id, chips}

  # No setup needed - application starts automatically with mix test

  describe "concurrent game creation" do
    test "multiple games can be created simultaneously without conflicts" do
      # Create multiple games concurrently
      tasks =
        1..10
        |> Enum.map(fn i ->
          Task.async(fn ->
            players = for j <- 1..6, do: player("#{i}_#{j}", 1500)
            GameManager.create_game(players)
          end)
        end)

      # Wait for all games to complete
      results = Task.await_many(tasks, 5000)

      # All games should be created successfully
      assert length(results) == 10

      Enum.each(results, fn result ->
        assert {:ok, game_id} = result
        assert is_binary(game_id)
      end)

      # All game IDs should be unique
      game_ids = Enum.map(results, fn {:ok, game_id} -> game_id end)
      assert length(Enum.uniq(game_ids)) == 10

      # All games should be listed (may include games from other tests)
      games_list = GameManager.list_games()
      assert length(games_list) >= 10
    end

    test "game creation during active operations" do
      # Create initial game
      players = for i <- 1..3, do: player(i, 1500)
      {:ok, game_id} = GameManager.create_game(players)

      # Start concurrent operations on existing game and create new games
      tasks = [
        # Lookup existing game repeatedly
        Task.async(fn ->
          for _i <- 1..50 do
            GameManager.lookup_game(game_id)
            Process.sleep(1)
          end

          :lookup_complete
        end),

        # Create new games concurrently
        Task.async(fn ->
          for i <- 1..5 do
            new_players = for j <- 1..3, do: player("new_#{i}_#{j}", 1500)
            GameManager.create_game(new_players)
          end

          :creation_complete
        end)
      ]

      results = Task.await_many(tasks, 5000)

      # Both operations should complete successfully
      assert :lookup_complete in results
      assert :creation_complete in results

      # Total games should be at least 6 (1 initial + 5 new, may include others from other tests)
      games_list = GameManager.list_games()
      assert length(games_list) >= 6
    end
  end

  describe "concurrent game lookups" do
    test "registry lookups are consistent under concurrent access" do
      # Create a test game
      players = for i <- 1..3, do: player(i, 1500)
      {:ok, game_id} = GameManager.create_game(players)

      # Perform many concurrent lookups
      tasks =
        1..100
        |> Enum.map(fn _i ->
          Task.async(fn ->
            GameManager.lookup_game(game_id)
          end)
        end)

      results = Task.await_many(tasks, 5000)

      # All lookups should return the same PID
      assert length(results) == 100

      # Extract PIDs and ensure they're all the same
      pids =
        Enum.map(results, fn
          {:ok, pid} -> pid
          other -> other
        end)

      # All results should be successful
      Enum.each(results, fn result ->
        assert {:ok, _pid} = result
      end)

      # All PIDs should be identical (same game process)
      unique_pids = Enum.uniq(pids)
      assert length(unique_pids) == 1
    end

    test "lookup of non-existent game during concurrent operations" do
      # Perform concurrent lookups of non-existent games
      fake_game_ids = for i <- 1..10, do: "fake_game_#{i}"

      tasks =
        fake_game_ids
        |> Enum.map(fn game_id ->
          Task.async(fn ->
            GameManager.lookup_game(game_id)
          end)
        end)

      results = Task.await_many(tasks, 5000)

      # All lookups should return consistent error
      assert length(results) == 10

      Enum.each(results, fn result ->
        assert {:error, :game_not_found} = result
      end)
    end
  end

  describe "game manager state consistency" do
    test "rapid game creation and listing maintains consistency" do
      # Continuously create games while listing them
      game_creation_task =
        Task.async(fn ->
          for i <- 1..20 do
            players = for j <- 1..3, do: player("rapid_#{i}_#{j}", 1500)
            GameManager.create_game(players)
            # Occasional pause
            if rem(i, 5) == 0, do: Process.sleep(1)
          end

          :creation_done
        end)

      listing_task =
        Task.async(fn ->
          game_counts =
            for _i <- 1..50 do
              games = GameManager.list_games()
              length(games)
            end

          game_counts
        end)

      [creation_result, listing_result] =
        Task.await_many([game_creation_task, listing_task], 5000)

      assert creation_result == :creation_done
      assert is_list(listing_result)

      # Final count should be at least 20 games (may include games from other tests)
      final_games = GameManager.list_games()
      assert length(final_games) >= 20

      # Game counts should generally increase (eventual consistency)
      # Last count should be higher than first count
      assert List.last(listing_result) >= List.first(listing_result)
    end
  end

  describe "supervision tree resilience" do
    test "game manager survives concurrent operation failures" do
      # Create some legitimate games
      players = for i <- 1..3, do: player(i, 1500)
      {:ok, game_id} = GameManager.create_game(players)

      # Attempt some operations that might cause issues
      tasks = [
        # Valid operations
        Task.async(fn -> GameManager.lookup_game(game_id) end),
        Task.async(fn -> GameManager.list_games() end),

        # Invalid operations that shouldn't crash the manager
        Task.async(fn -> GameManager.lookup_game("") end),
        Task.async(fn -> GameManager.lookup_game(nil) end)
      ]

      # Some tasks might fail, but the GameManager should survive
      try do
        Task.await_many(tasks, 5000)
      rescue
        # Expected for invalid inputs
        _error -> :some_operations_failed
      end

      # GameManager should still be functional
      assert {:ok, _new_game_id} = GameManager.create_game(players)
      games = GameManager.list_games()
      # At least one game should exist
      assert length(games) >= 1
    end
  end
end
