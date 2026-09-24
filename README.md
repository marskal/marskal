# Marskal Tasks

Personal soft-GTD task manager (recurring tasks, planning, nested tasks).

Product rules: **[AGENTS.md](AGENTS.md)**. Decisions: **[docs/adr/](docs/adr/)**.

## Layout

| Path | What |
|------|------|
| [`web/`](web/) | The web app, including `devenv.nix`. Rails until the [Phoenix port](docs/adr/0016-elixir-phoenix-web.md). |
| [`docs/adr/`](docs/adr/) | Architecture decisions. |

`sync/fixtures/` and `clients/ios/` are not created until that work starts
([ADR 0015](docs/adr/0015-repository-layout.md)).

## Web app

```bash
cd web
devenv up
```

Open **http://marskal.localhost:8275**. Setup, seed accounts, and the rest of
the local workflow are in **[web/README.md](web/README.md)**.
