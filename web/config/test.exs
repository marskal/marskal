import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :argon2_elixir,
  t_cost: 1,
  m_cost: 8

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :marskal, Marskal.Repo,
  username: System.get_env("PGUSER") || System.get_env("USER") || "postgres",
  password: System.get_env("PGPASSWORD"),
  hostname: System.get_env("PGHOST") || "127.0.0.1",
  port: String.to_integer(System.get_env("PGPORT") || "8271"),
  database: "marskal_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :marskal, MarskalWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "i68JpIdbAVP5FVDHZlFp6v3Nt8EZjbi+K9lXWzUY6NUFOZHGPB3P19YUNztlK/Cm",
  server: false

# In test we don't send emails
config :marskal, Marskal.Mailer, adapter: Swoosh.Adapters.Test

# Jobs are inserted, then a test drains them. They do not run inside the request.
config :marskal, Oban, testing: :manual

# Todoist HTTP is stubbed. runtime.exs leaves these alone in test.
config :marskal, Marskal.Imports.Todoist,
  client_id: "todoist-client",
  client_secret: "todoist-secret",
  redirect_uri: "http://www.marskal.example/imports/todoist/callback",
  req_options: [plug: {Req.Test, Marskal.Imports.Todoist}]

# Hydra's admin API is stubbed (Marskal.HydraFixtures).
config :marskal, Marskal.Hydra,
  admin_url: "http://hydra-admin.test",
  public_url: "http://hydra.test",
  req_options: [plug: {Req.Test, Marskal.Hydra}]

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# The sync event stream on short timers (ADR 0030).
config :marskal, MarskalWeb.SyncEvents,
  keep_alive: 60_000,
  recheck: 100,
  coalesce: 20
