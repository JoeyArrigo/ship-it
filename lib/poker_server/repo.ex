defmodule PokerServer.Repo do
  use Ecto.Repo,
    otp_app: :poker_server,
    adapter: Ecto.Adapters.Postgres
end