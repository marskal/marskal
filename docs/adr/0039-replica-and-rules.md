# 0039. Replica and rules

## Status

Accepted

Amends [ADR 0018](0018-rust-client-sync-library.md): the client library is
two crates, `replica` and `rules`, not one at `sync/core`.

Amends [ADR 0015](0015-repository-layout.md): the shared Rust code and the
fixtures live under `core/`, not `sync/`.

## Context

ADR 0018 put the offline clients' engine in one crate, `sync/core`
(`marskal-sync`): the SQLite schema, the outbox, the pull merge, the reads
with their derived state, and the operations every shell shares.

The crate has since taken on rules that are not about sync or storage:
fractional rank, link ids, URL checks, the default time of a day for
Defer, Planned, and Due, and path search for tags and Go to. More are
coming: the typed-date grammar (ADR 0032) is to be ported next. These are
functions of plain values. They need no database, and Elixir implements
each of them too, checked by the same fixture vectors.

Mixed into the sync crate, they are hard to find, and a shell that only
wants one of them, such as a URL check in a capture window, links the
whole engine with SQLite. The name `sync` also undersells the rest of the
engine: it is the client's local copy of the user's data, which shells
read and write as much as they sync.

## Decision

Split the library in two, and move the shared Rust code to `core/`.

```text
core/rules/      # marskal-rules: the pure rules both sides implement
core/replica/    # marskal-replica: the local copy, its reads, writes, and sync
core/ffi/        # UniFFI over both, for iOS (ADR 0029)
core/fixtures/   # vectors Elixir and rules run
```

### `rules`

Functions of plain values: text, instants, ids, time zones. No SQLite, no
I/O, no domain rows, no clock of its own. Today that is `rank`, `ids`,
`url`, `dates`, and `path_search`; the typed-date grammar joins them when
it is ported. Each rule has an Elixir counterpart and vectors in
`core/fixtures`, generated from Elixir.

A rule belongs here when the server has the same function and a client
could call it without opening a database.

### `replica`

The client's local replica of the user's data (ADR 0014): the SQLite
schema and migrations, the domain rows, the outbox, the pull merge, the
reads with the state the server derives (effective dates and tags,
availability, the agenda, tag search over the stored tags), and the
operations. It depends on `rules` and does not re-export it. The main
type stays `Store`.

Everything ADR 0018 says of the library holds for `replica`: it does no
HTTP, keeps no secrets, schedules nothing, and draws no UI.

### Shells

A Rust shell depends on `replica`, on `rules`, or on both, by path. A
shell that only needs a rule, such as a capture window checking a URL,
depends on `rules` alone. The FFI crate wraps both for Swift, and a later
Android shell uses it the same way. The web app calls neither (ADR 0018).

### Alternatives considered

- **Keep one crate, rename it.** Rejected. A better name does not stop a
  capture-only shell linking SQLite, and the pure rules stay mixed with the
  merge code.
- **Keep the `sync/` directory.** Rejected. It would hold rules that are
  not sync, which is the problem this ADR fixes.
- **`engine`, `store`, `local`, or `offline` for the replica.** Rejected.
  `engine` and `local` say little; `store` says storage but not sync;
  `offline` misdescribes a client that is online most of the time.
- **Fixtures inside `rules/`.** Rejected. They are the contract between
  Elixir and Rust, not part of either; `core/fixtures` sits beside both
  crates.

## Consequences

- The move is one change of its own, before more features: `sync/core`
  becomes `core/replica` and `core/rules`, `sync/ffi` becomes `core/ffi`,
  and `sync/fixtures` becomes `core/fixtures`. Each crate keeps its own
  `devenv.nix` and `Cargo.lock`; there is still no root Cargo workspace
  (ADR 0018).
- Every path dependency, Nix package, README, script, Dependabot entry,
  and the changelog check that names `sync/` moves with it:
  `clients/terminal`, `clients/ios`, `clients/shell-common`, and any shell
  started before the move.
  `Marskal.SyncFixturesTest` reads `core/fixtures` and is renamed
  `Marskal.FixturesTest`.
- `AGENTS.md` follows the move in the same change.
- A new pure rule goes in `rules` with vectors; a new read or operation
  goes in `replica`. Neither crate grows HTTP, secrets, or UI.
