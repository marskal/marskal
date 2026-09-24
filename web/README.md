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
| `mts@marskal.example` | `H3mm3l1gh3d` | Superuser. Inbox, open tasks, and `/dev/dashboard`. |
| `kvp@marskal.example` | `H3mm3l1gh3d` | Second user, for isolation. |

The seed is idempotent. It adds the sample folders and projects when the
account does not have any yet. OmniFocus import is not ported yet. The
tutorial backup is at `test/fixtures/files/omnifocus-tutorial.ofocus-backup.zip`.

`devenv shell` then `mix test` runs the suite. Postgres must already be up
(`devenv up` or `devenv processes start postgres`).

There is no `devenv.nix` at the repository root.
