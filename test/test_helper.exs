ExUnit.start()

# Only set up database sandbox if using production persistence
case Application.get_env(:poker_server, :tournament_persistence) do
  PokerServer.Tournament.ProductionPersistence ->
    Ecto.Adapters.SQL.Sandbox.mode(PokerServer.Repo, :manual)
  _ ->
    :ok
end
