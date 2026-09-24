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

Open **http://marskal.localhost:8275**. Register at `/users/register`.

`devenv shell` then `mix test` runs the suite. Postgres must already be up
(`devenv up` or `devenv processes start postgres`).

There is no `devenv.nix` at the repository root.
