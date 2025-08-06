import Config

# Configure your database
# config :poker_server, PokerServer.Repo,
#   username: "postgres",
#   password: "postgres",
#   hostname: "localhost",
#   database: "poker_server_dev",
#   stacktrace: true,
#   show_sensitive_data_on_connection_error: true,
#   pool_size: 10

# For development, we disable any cache and enable
# debugging and code reloading.
config :poker_server, PokerServerWeb.Endpoint,
  # Binding to all interfaces to allow access from other machines on the network
  http: [ip: {0, 0, 0, 0}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "poker_dev_secret_key_base_that_is_at_least_64_characters_long_and_secure",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:poker_server, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:poker_server, ~w(--watch)]}
  ]

# Watch static and templates for browser reloading.
config :poker_server, PokerServerWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/(?!uploads/).*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"priv/gettext/.*(po)$",
      ~r"lib/poker_server_web/(controllers|live|components)/.*(ex|heex)$"
    ]
  ]

# Enable dev routes for dashboard and mailbox
config :poker_server, dev_routes: true

# Do not include metadata nor timestamps in development logs
config :logger, :console, format: "[$level] $message\n"

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime

# Include HEEx debug annotations as HTML comments in rendered markup
config :phoenix_live_view, :debug_heex_annotations, true

# Disable swoosh api client as it is only required for production adapters.
# config :swoosh, :api_client, false