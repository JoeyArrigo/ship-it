defmodule PokerServer.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  require Logger

  # Get the configured persistence implementation to determine if we need database
  @persistence_module Application.compile_env(:poker_server, :tournament_persistence)

  @impl true
  def start(_type, _args) do
    children = database_children() ++ [
      # Phoenix PubSub for real-time communication
      {Phoenix.PubSub, name: PokerServer.PubSub},

      # Registry for looking up game processes by ID
      {Registry, keys: :unique, name: PokerServer.GameRegistry},

      # Tournament supervisor with recovery support
      PokerServer.TournamentSupervisor,
      
      # Tournament persistence handler for event-driven architecture
      PokerServer.Tournament.PersistenceHandler,

      # Game manager that coordinates games
      PokerServer.GameManager,

      # Game queue for matchmaking
      PokerServer.GameQueue,

      # Telemetry supervisor
      PokerServerWeb.Telemetry,

      # Phoenix endpoint
      PokerServerWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: PokerServer.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Database children - only include if using production persistence (compile-time decision)
  defp database_children do
    if @persistence_module == PokerServer.Tournament.ProductionPersistence do
      [PokerServer.Repo]
    else
      []
    end
  end
end
