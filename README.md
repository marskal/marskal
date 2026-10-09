# Marskal Tasks

Personal soft-GTD task manager (recurring tasks, planning, nested tasks).

Product rules: **[AGENTS.md](AGENTS.md)**. Decisions: **[docs/adr/](docs/adr/)**.

## Layout

| Path | What |
|------|------|
| [`web/`](web/) | The Phoenix app, including `devenv.nix`. |
| [`docs/adr/`](docs/adr/) | Architecture decisions. |

`sync/fixtures/`, `sync/core/`, and `clients/` are not created until that work
starts ([ADR 0015](docs/adr/0015-repository-layout.md),
[ADR 0018](docs/adr/0018-rust-client-sync-library.md)).

## Web app and API server

```bash
cd web
devenv up
```

Open **http://marskal.localhost:8275**. Setup, seed accounts, and the rest of
the local workflow are in **[web/README.md](web/README.md)**.
