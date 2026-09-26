# 0004. Hosting: NixOS VPS; local is development only

## Status

Accepted

## Context

For now, the app is hosted on a NixOS server, configured elsewhere.

## Decision

- **Development:** devenv on the local machine. `devenv.nix` lives in `web/`
  ([ADR 0015](0015-repository-layout.md)).
- **Packaging:** `web/flake.nix` exports the release as
  `packages.x86_64-linux.default` and a NixOS module as
  `nixosModules.default`. The release is built with nixpkgs' `mixRelease`.
  The flake pins the same nixpkgs as devenv, so production runs the
  Elixir/OTP that was tested locally. The flake sits in `web/` because it
  builds that program only; consumers reference it with `?dir=web`.
- **Deploy:** The host NixOS system takes marskal as a flake input and enables
  `services.marskal`.
- **The module owns its runtime:**
  - Postgres 18 on the same host, reached over the unix socket with peer auth.
  - Migrations run before each start.
  - Phoenix listens on loopback behind nginx, which terminates TLS.
  - `SECRET_KEY_BASE` and `RELEASE_COOKIE` are generated once into
    `/var/lib/marskal/secrets.env`.
- Config via environment (`DATABASE_URL`, `SECRET_KEY_BASE`, `PHX_HOST`, …),
  not laptop-only paths.

## Consequences

- A change to `mix.lock` changes the name of the deps derivation. The build
  then fails with a hash mismatch until `depsHash` in `web/nix/package.nix`
  is updated. It never silently reuses stale deps.
- Deps that download binaries at compile time need a Nix-side answer.
  esbuild comes from nixpkgs (`MIX_ESBUILD_PATH`). mdex_native's NIF is
  pre-fetched per system. A new dep of this kind breaks the build until it
  gets the same treatment.
- Keep `config :esbuild, version:` in step with nixpkgs' esbuild.
- The Nix build targets x86_64-linux only. Adding a system means listing
  its mdex_native NIF.
- Backups, secrets beyond the generated pair, and outgoing mail are still
  open. Prod has no Swoosh adapter yet, so email-change confirmation does
  not deliver.
