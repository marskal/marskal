defmodule Marskal.MixProject do
  use Mix.Project

  def project do
    [
      app: :marskal,
      version: "0.2.0",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      # Files without line numbers, sorted, so moving code does not touch them.
      gettext: [write_reference_line_numbers: false, sort_by_msgid: :case_sensitive],
      dialyzer: [
        plt_add_apps: [:ex_unit],
        ignore_warnings: ".dialyzer_ignore.exs"
      ],
      package: [licenses: ["Apache-2.0"]]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Marskal.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test, ci: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:argon2_elixir, "~> 4.0"},
      {:oban, "~> 2.20"},
      {:mdex, "~> 0.13"},
      {:lucide_icons, "~> 2.4"},
      {:tz, "~> 0.28"},
      {:ex_cldr_dates_times, "~> 2.25"},
      {:phoenix_live_dashboard, "~> 0.8"},
      {:phoenix, "~> 1.8.14"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.2.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:swoosh, "~> 1.16"},
      {:req, "~> 0.5"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.3"},
      {:bandit, "~> 1.5"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_dna, "~> 1.5", only: [:dev, :test], runtime: false},
      {:ex_slop, "~> 0.4", only: [:dev, :test], runtime: false},
      {:reach, "~> 2.8", only: [:dev, :test], runtime: false}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["esbuild.install --if-missing", "cmd --cd assets npm ci"],
      "assets.check": ["compile", "cmd --cd assets npm run --silent typecheck"],
      "assets.build": ["compile", "esbuild marskal"],
      "assets.deploy": [
        "esbuild marskal --minify",
        "phx.digest"
      ],
      precommit: [
        "compile --warnings-as-errors",
        "assets.check",
        "deps.unlock --unused",
        "format",
        "gettext.extract",
        "test",
        "credo --strict",
        "dialyzer",
        "ex_dna --max-clones 5",
        "reach.check --arch --smells"
      ],
      ci: [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "gettext.extract --check-up-to-date",
        "test",
        "credo --strict",
        "dialyzer",
        "ex_dna --max-clones 5",
        "reach.check --arch --smells"
      ]
    ]
  end
end
