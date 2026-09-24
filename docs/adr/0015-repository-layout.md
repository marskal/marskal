# 0015. Repository layout

## Status

Accepted

## Context

The web app will be joined by an offline iOS client (ADR 0014). Those two
programs share a contract, the recurrence fixture vectors, and nothing else.
Separate repositories would let that contract drift. An empty client tree, or a
directory named `server/` that also holds the LiveView, would obscure which
program is which.

The web app is one program. LiveView calls the domain in-process. It is not a
sibling of the iOS app. `devenv` belongs to that program: it provides the
language toolchain, Postgres, and the web process, and it stores the local
database in `.devenv/` beside `devenv.nix`. devenv also walks up from the
working directory until it finds a `devenv.nix`, so a copy at the repository
root would activate inside a future `clients/ios`.

## Decision

One repository. The root is the product, not the web app.

```text
docs/adr/          # product decisions
web/               # the web app, including devenv.nix
sync/fixtures/     # recurrence vectors — create with that work, not before
clients/ios/       # SwiftUI, widget, App Intents — create when that work starts
```

- **`web/`** is the online client and the host: domain, sync endpoint, and
  LiveView. The tree is Rails until the port replaces it
  ([ADR 0016](0016-elixir-phoenix-web.md)). Do not name this directory
  `server/`, and do not extract the UI to `clients/web`. Do not add a second
  app directory beside `web/`.
- **`devenv.nix` and `devenv.lock` live in `web/`.** Run `devenv shell` and
  `devenv up` from there. No root `devenv.nix`, and no root file whose only job
  is to `cd web`.
- **Do not create `clients/ios/` or `sync/fixtures/` until that work starts.**
  The iOS app is not an Elixir umbrella app. Android, if it ever exists, is a
  sibling directory reading the same fixtures, not a shared native core.
- **Docs stay at the root.** `AGENTS.md` and `docs/` describe the product.
  Paths in the web-app conventions are relative to `web/`.
- **Versions stay independent.** The web app deploys by commit. An App Store
  build number is not a git tag.

## Consequences

- Development is `cd web && devenv up`. The local Postgres cluster is
  `web/.devenv/`. Moving `devenv.nix` without that directory orphans it.
- Docker and Kamal run with `web/` as the context. GitHub workflows, which
  must live at the repository root, set their working directory to `web/`.
- A root `devenv.nix` is a bug, not a convenience. Add one only when a second
  Nix-built program exists, and do not let it wrap the web app.
