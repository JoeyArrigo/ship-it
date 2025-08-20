defmodule PokerServer.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    children = [
      # Phoenix PubSub for real-time communication
      {Phoenix.PubSub, name: PokerServer.PubSub},

      # Registry for looking up game processes by ID
      {Registry, keys: :unique, name: PokerServer.GameRegistry},

      # Dynamic supervisor for individual game processes  
      {DynamicSupervisor, name: PokerServer.GameSupervisor, strategy: :one_for_one},

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
end
