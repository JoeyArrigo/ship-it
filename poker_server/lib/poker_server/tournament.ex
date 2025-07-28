defmodule PokerServer.Tournament do
  @moduledoc """
  Tournament features for poker server including blind level progression.
  """

  defstruct [
    :id,
    :name,
    :current_level,
    :level_start_time,
    :level_duration_minutes,
    :blind_levels,
    :status
  ]

  @doc """
  Create a new tournament with standard blind structure.
  """
  def new(id, name, options \\ []) do
    level_duration = Keyword.get(options, :level_duration_minutes, 10)
    blind_levels = Keyword.get(options, :blind_levels, default_blind_levels())
    
    %__MODULE__{
      id: id,
      name: name,
      current_level: 1,
      level_start_time: DateTime.utc_now(),
      level_duration_minutes: level_duration,
      blind_levels: blind_levels,
      status: :active
    }
  end

  @doc """
  Default tournament blind structure (standard progression).
  """
  def default_blind_levels do
    [
      {1, 10, 20},     # Level 1: 10/20
      {2, 15, 30},     # Level 2: 15/30
      {3, 25, 50},     # Level 3: 25/50
      {4, 50, 100},    # Level 4: 50/100
      {5, 75, 150},    # Level 5: 75/150
      {6, 100, 200},   # Level 6: 100/200
      {7, 150, 300},   # Level 7: 150/300
      {8, 200, 400},   # Level 8: 200/400
      {9, 300, 600},   # Level 9: 300/600
      {10, 500, 1000}, # Level 10: 500/1000
      {11, 750, 1500}, # Level 11: 750/1500
      {12, 1000, 2000} # Level 12: 1000/2000
    ]
  end

  @doc """
  Get current blind levels for the tournament.
  """
  def current_blinds(tournament) do
    case Enum.find(tournament.blind_levels, fn {level, _sb, _bb} -> 
      level == tournament.current_level 
    end) do
      {_level, small_blind, big_blind} -> {small_blind, big_blind}
      nil -> {10, 20}  # Fallback to minimum blinds
    end
  end

  @doc """
  Check if it's time to advance to the next blind level.
  """
  def time_to_advance?(tournament) do
    now = DateTime.utc_now()
    minutes_elapsed = DateTime.diff(now, tournament.level_start_time, :second) / 60
    minutes_elapsed >= tournament.level_duration_minutes
  end

  @doc """
  Advance tournament to the next blind level.
  """
  def advance_level(tournament) do
    next_level = tournament.current_level + 1
    max_level = tournament.blind_levels |> Enum.map(&elem(&1, 0)) |> Enum.max()
    
    if next_level <= max_level do
      %{tournament |
        current_level: next_level,
        level_start_time: DateTime.utc_now()
      }
    else
      # Tournament has reached maximum blind level
      tournament
    end
  end

  @doc """
  Get remaining time in current level (in minutes).
  """
  def time_remaining(tournament) do
    now = DateTime.utc_now()
    minutes_elapsed = DateTime.diff(now, tournament.level_start_time, :second) / 60
    max(0, tournament.level_duration_minutes - minutes_elapsed)
  end

  @doc """
  Update tournament clock and advance level if needed.
  """
  def tick(tournament) do
    if time_to_advance?(tournament) do
      {:level_up, advance_level(tournament)}
    else
      {:continue, tournament}
    end
  end

  @doc """
  Get tournament status summary.
  """
  def status(tournament) do
    {small_blind, big_blind} = current_blinds(tournament)
    
    %{
      id: tournament.id,
      name: tournament.name,
      current_level: tournament.current_level,
      small_blind: small_blind,
      big_blind: big_blind,
      time_remaining_minutes: time_remaining(tournament),
      status: tournament.status
    }
  end
end