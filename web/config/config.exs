# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :marskal, :scopes,
  user: [
    default: true,
    module: Marskal.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :binary_id,
    schema_table: :users,
    test_data_fixture: Marskal.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :marskal,
  ecto_repos: [Marskal.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :marskal, MarskalWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: MarskalWeb.ErrorHTML, json: MarskalWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Marskal.PubSub,
  live_view: [signing_salt: "kbvKcrVt"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :marskal, Marskal.Mailer, adapter: Swoosh.Adapters.Local

config :marskal, Oban,
  repo: Marskal.Repo,
  queues: [default: 10, imports: 2],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    {Oban.Plugins.Cron,
     crontab: [
       {"@hourly", Marskal.Imports.ExpireJob}
     ]}
  ]

# Configure esbuild (the version is required). The Nix build supplies its
# own binary through MIX_ESBUILD_PATH instead of downloading one; keep the
# version in step with nixpkgs' esbuild.
config :esbuild,
  version: "0.27.2",
  path: System.get_env("MIX_ESBUILD_PATH"),
  marskal: [
    args:
      ~w(js/app.ts --bundle --target=es2024 --outdir=../priv/static/assets/js --loader:.woff2=file --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Dates show in the user's stored zone (ADR 0006). tz ships the IANA data,
# so nothing is downloaded at compile or run time.
config :elixir, :time_zone_database, Tz.TimeZoneDatabase

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
