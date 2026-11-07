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

## Self-hosting

Marskal is self-hosted: you run your own server. Documentation for doing so
will be provided in due time. Until then, the server is packaged as a NixOS
module, `nixosModules.default` in [`web/flake.nix`](web/flake.nix)
([ADR 0004](docs/adr/0004-hosting-vps-nix.md)). Serve it over HTTPS; the
Thunderbird add-on connects only over HTTPS.

## License

Copyright 2026 Mikkel T. Hoegh. Licensed under the
[Apache License, Version 2.0](LICENSE).
