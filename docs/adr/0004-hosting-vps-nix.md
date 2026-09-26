# 0004. Hosting: VPS (Nix); local is development only

## Status

Accepted

## Context

Need a production target that matches a normal multi-user Rails + Postgres app.
Local-only and PaaS-first (Fly, Heroku, etc.) were considered; the preference is
direct VPS control, likely with Nix.

## Decision

- **Development:** devenv on the local machine (Ruby, Bundler, Postgres, app processes).
  `devenv.nix` lives in `web/` ([ADR 0015](0015-repository-layout.md)).
- **Production:** **VPS**, configuration preferably with **Nix** (NixOS and/or Nix-based deploys).
- Local is **not** a production runtime.
- Config via environment (`DATABASE_URL`, `SECRET_KEY_BASE`, etc.), not laptop-only paths.
- Do not assume PaaS-specific APIs as the primary deploy model.

Concrete provider and NixOS vs Nix-on-distro remain open until deploy work starts.

## Consequences

- App should stay a portable Rails service (web + optional jobs) against Postgres.
- Secrets, TLS, backups, and process supervision are VPS concerns.
- Deploy docs/automation can live under Nix without forcing Heroku-style constraints.
