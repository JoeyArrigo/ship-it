import Config

# Configure your database for tests
config :poker_server, PokerServer.Repo,
  username: System.get_env("DATABASE_USERNAME") || raise("DATABASE_USERNAME environment variable is required"),
  password: System.get_env("DATABASE_PASSWORD") || raise("DATABASE_PASSWORD environment variable is required"),
  hostname: System.get_env("DATABASE_HOST") || raise("DATABASE_HOST environment variable is required"),
  database: "poker_server_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :poker_server, PokerServerWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: System.get_env("SECRET_KEY_BASE") || raise("SECRET_KEY_BASE environment variable is required"),
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime