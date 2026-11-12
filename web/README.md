# Marskal web app

Phoenix + LiveView. Commands below run from this directory (`web/`).

Product rules: **[AGENTS.md](../AGENTS.md)**. Decisions: **[docs/adr/](../docs/adr/)**.

## Stack

- Elixir 1.20, Erlang/OTP 29 (pinned in `devenv.nix`)
- Phoenix 1.8, LiveView 1.2, Bandit
- PostgreSQL 18 (devenv service)
- Ecto. Domain ids are `uuid` with `DEFAULT uuidv7()`

## Local development

```bash
devenv up
```

Open **http://marskal.localhost:8275**. Register at `/users/register`, or load the
sample accounts:

```bash
mix run priv/repo/seeds.exs
```

| Email | Password | |
|-------|----------|--|
| `mts@marskal.test` | `H3mm3l1gh3d` | Marie-Thérèse Scheuner-Mäder. Superuser. Inbox, open tasks, and `/dev/dashboard`. |
| `kvp@marskal.test` | `H3mm3l1gh3d` | Karl-Viggo von und zu Pappenheim. Second user, for isolation. |
| `edb@marskal.test` | `H3mm3l1gh3d` | Evald Daugård Berthelsen. Danish fixture. Projects, tasks, tags, reviews, and repeats. Locale `da`, agenda home, Vim-style keys. |

The seed is idempotent. It adds the sample folders and projects when the
account does not have any yet. The Danish account is filled once, when it
has no projects; later runs leave that data and reset its preferences. An
account still at its old `@marskal.example` address moves to the new one.
Import is at `/imports`.

OmniFocus: upload a Backup Document (`.ofocus-backup` or a zip of one). The
tutorial backup used by the tests is
`test/fixtures/files/omnifocus-tutorial.ofocus-backup.zip`.

Todoist: sign in with OAuth. Register an app under Todoist Settings →
Integrations → App Management, with the redirect
`http://marskal.localhost:8275/imports/todoist/callback`. Put the credentials
in the environment that starts the app:

```bash
export TODOIST_CLIENT_ID=...
export TODOIST_CLIENT_SECRET=...
```

The scope is read-only. The access token downloads one sync snapshot and is
not stored. Parsing and applying run on the Oban `imports` queue; the page
refreshes until the job finishes.

`devenv shell` installs the npm packages in `assets/`. `mix assets.check`
type-checks the TypeScript, colocated hooks included.

`devenv shell` then `mix test` runs the suite. Postgres must already be up
(`devenv up` or `devenv processes start postgres`).

There is no `devenv.nix` at the repository root.
