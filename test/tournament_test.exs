defmodule PokerServer.TournamentTest do
  use ExUnit.Case
  alias PokerServer.Tournament

  describe "tournament creation" do
    test "creates tournament with default settings" do
      tournament = Tournament.new("t1", "Test Tournament")

      assert tournament.id == "t1"
      assert tournament.name == "Test Tournament"
      assert tournament.current_level == 1
      assert tournament.level_duration_minutes == 10
      assert tournament.status == :active
      assert is_list(tournament.blind_levels)
      assert length(tournament.blind_levels) > 0
    end

    test "creates tournament with custom settings" do
      custom_levels = [{1, 5, 10}, {2, 10, 20}]

      tournament =
        Tournament.new("t2", "Custom Tournament",
          level_duration_minutes: 15,
          blind_levels: custom_levels
        )

      assert tournament.level_duration_minutes == 15
      assert tournament.blind_levels == custom_levels
    end
  end

  describe "blind level management" do
    test "gets current blinds for level 1" do
      tournament = Tournament.new("t1", "Test")
      {small_blind, big_blind} = Tournament.current_blinds(tournament)

      assert small_blind == 10
      assert big_blind == 20
    end

    test "gets current blinds for higher levels" do
      tournament = Tournament.new("t1", "Test")
      tournament = %{tournament | current_level: 4}

      {small_blind, big_blind} = Tournament.current_blinds(tournament)
      assert small_blind == 50
      assert big_blind == 100
    end

    test "handles invalid level gracefully" do
      tournament = Tournament.new("t1", "Test")
      tournament = %{tournament | current_level: 999}

      {small_blind, big_blind} = Tournament.current_blinds(tournament)
      # Fallback
      assert small_blind == 10
      # Fallback
      assert big_blind == 20
    end
  end

  describe "level advancement timing" do
    test "time_to_advance? returns false for new tournament" do
      tournament = Tournament.new("t1", "Test")
      refute Tournament.time_to_advance?(tournament)
    end

    test "time_to_advance? returns true after time elapses" do
      # Create tournament with past start time
      past_time = DateTime.add(DateTime.utc_now(), -15, :minute)
      tournament = Tournament.new("t1", "Test", level_duration_minutes: 10)
      tournament = %{tournament | level_start_time: past_time}

      assert Tournament.time_to_advance?(tournament)
    end

    test "advance_level increments level and resets timer" do
      tournament = Tournament.new("t1", "Test")
      original_time = tournament.level_start_time

      advanced = Tournament.advance_level(tournament)

      assert advanced.current_level == 2
      assert DateTime.compare(advanced.level_start_time, original_time) == :gt
    end

    test "advance_level stops at maximum level" do
      custom_levels = [{1, 10, 20}, {2, 20, 40}]
      tournament = Tournament.new("t1", "Test", blind_levels: custom_levels)
      tournament = %{tournament | current_level: 2}

      # Try to advance beyond max level
      advanced = Tournament.advance_level(tournament)

      # Should stay at max level
      assert advanced.current_level == 2
    end
  end

  describe "tournament clock" do
    test "tick returns :continue when time remaining" do
      tournament = Tournament.new("t1", "Test")

      {result, _tournament} = Tournament.tick(tournament)
      assert result == :continue
    end

    test "tick returns :level_up when time elapsed" do
      # Create tournament with past start time
      past_time = DateTime.add(DateTime.utc_now(), -15, :minute)
      tournament = Tournament.new("t1", "Test", level_duration_minutes: 10)
      tournament = %{tournament | level_start_time: past_time}

      {result, updated_tournament} = Tournament.tick(tournament)
      assert result == :level_up
      assert updated_tournament.current_level == 2
    end

    test "time_remaining calculates correctly" do
      tournament = Tournament.new("t1", "Test", level_duration_minutes: 10)

      remaining = Tournament.time_remaining(tournament)
      # Should be close to 10 minutes
      assert remaining > 9.9 and remaining <= 10.0
    end

    test "time_remaining returns 0 when time expired" do
      # Create tournament with past start time
      past_time = DateTime.add(DateTime.utc_now(), -15, :minute)
      tournament = Tournament.new("t1", "Test", level_duration_minutes: 10)
      tournament = %{tournament | level_start_time: past_time}

      remaining = Tournament.time_remaining(tournament)
      assert remaining == 0
    end
  end

  describe "tournament status" do
    test "status returns comprehensive tournament info" do
      tournament = Tournament.new("t1", "Test Tournament")
      status = Tournament.status(tournament)

      assert status.id == "t1"
      assert status.name == "Test Tournament"
      assert status.current_level == 1
      assert status.small_blind == 10
      assert status.big_blind == 20
      assert status.time_remaining_minutes > 0
      assert status.status == :active
    end

    test "status reflects current level blinds" do
      tournament = Tournament.new("t1", "Test")
      tournament = %{tournament | current_level: 3}

      status = Tournament.status(tournament)
      assert status.small_blind == 25
      assert status.big_blind == 50
    end
  end

  describe "default blind structure" do
    test "has reasonable progression" do
      levels = Tournament.default_blind_levels()

      # Should have multiple levels
      assert length(levels) >= 10

      # Verify structure: {level, small_blind, big_blind}
      Enum.each(levels, fn {level, sb, bb} ->
        assert is_integer(level)
        assert is_integer(sb)
        assert is_integer(bb)
        # Big blind should be 2x small blind
        assert bb == sb * 2
      end)

      # Verify levels are increasing
      level_numbers = Enum.map(levels, &elem(&1, 0))
      assert level_numbers == Enum.sort(level_numbers)

      # Verify blinds are increasing
      small_blinds = Enum.map(levels, &elem(&1, 1))
      assert small_blinds == Enum.sort(small_blinds)
    end
  end
end
