# 0018. Rust client sync library

## Status

Accepted

Amends the client set in [ADR 0014](0014-offline-sync.md): desktop, Android,
iOS, and an optional terminal client share one engine. The protocol is
unchanged.

Amends [ADR 0015](0015-repository-layout.md): those clients share a Rust
library. They still do not share a UI, and the web app does not call the
library.

Shells amended by [ADR 0020](0020-terminal-client.md): the terminal client is
one program, `clients/terminal`, not `clients/tui`.

Amended 2026-11-08: the Rust shells share sign-in and file locations through
`clients/shell-common`, and the reasons for keeping every crate out of a
Cargo workspace are recorded under "Rust crates and builds".

Amended by [ADR 0039](0039-replica-and-rules.md): the library is two crates,
`core/replica` and `core/rules`, and the fixtures are in `core/fixtures`.

## Context

ADR 0014 specifies offline sync and assumed one native client, an iOS app,
with the client rules ported to Swift and checked by fixture vectors. ADR 0015
put that app in `clients/ios` and said Android, if it ever existed, would be a
sibling reading the same fixtures, not a shared native core.

The intended clients are now a cross-platform desktop app, Android, iOS (the
app, the widget, and Shortcuts), and possibly a terminal UI. Each needs a
local database, an outbox, and the merge rules. Those rules are where a second
implementation loses a check-off or mints a duplicate occurrence. Four ports
is a different cost from the one Swift port ADR 0014 accepted.

The server is not one of those ports. It is the authority, it has no outbox,
and LiveView calls the Elixir domain in-process. The pure rules the clients
use, such as ranks and link ids, still have to agree across that boundary.

## Decision

Offline clients share one Rust library at `sync/core`. Create it with the
first offline client, and not before the server pull endpoint exists. Do not
create the directory before that.

The library is the client engine for [ADR 0014](0014-offline-sync.md). It
owns:

- The local **SQLite** schema and its migrations. One file. Not Postgres.
- The **outbox**: field patches and command ids.
- The **pull merge**. A field with a pending local edit keeps the local value.
  Every other field takes the server value. Discard wins. `resolved_at` is
  first-write.
- **Fractional rank**, tag `merged_into_id`, and the derived fields
  (`parent_path`, effective tags), recomputed after applying patches.
- **Recurrence series** and their occurrences, as stored rows. The server
  creates every occurrence (ADR 0014, amended 2026-10-03); the library does
  not spawn, so it has no calendar math to keep in step.

The exported API is coarse and synchronous: open the database, apply a
command, apply a pull response, read tasks. The library does not perform HTTP,
store secrets, schedule work, or draw a UI.

Shells own HTTP, the keychain or keystore, notifications, and the UI.

- **iOS and Android** call the library through **UniFFI**. On iOS the same
  static library links into the app, the widget extension, and the Shortcuts
  extension. The database file lives in the App Group. A widget check-off
  writes the outbox. The push waits until the app is open.
- A **Rust** shell, including a terminal UI, calls the crate in-process.
- A **non-Rust** desktop shell, if one is chosen, calls a **C ABI** over the
  same crate. This ADR does not choose the desktop toolkit.

Shells are sibling directories under `clients/`, created when that shell
starts: `clients/ios`, `clients/android`, `clients/desktop`, and `clients/tui`
only if a terminal client is built. Building them is later work. This ADR does
not schedule it.

The **server stays Elixir**. Do not call this library from Phoenix, and do not
put the domain behind a NIF. Elixir and the library are the two
implementations of the pure rules, and both run `sync/fixtures`. A new shell
does not add a third.

The iOS app is not an Elixir umbrella. There is no shared UI core.

### Rust crates and builds

What every Rust shell needs around the engine lives in one more crate,
**`clients/shell-common`** (`marskal-shell-common`): the XDG directories
(ADR 0020), the OAuth client and the device-grant poll (ADR 0021), and the
token store with its keychain fallback and refresh lock. It does no sync and
draws no UI. Each shell keeps its own client id, keychain names, messages,
and the sync calls it makes. The library still stores no secrets; the shells
do, through this crate.

Every Rust crate is its own Cargo project, with its own `Cargo.lock`,
`target/`, and `devenv.nix`. A crate uses another by path, as
`clients/terminal` uses `sync/core`. There is **no Cargo workspace**:

- **Toolchains differ.** `clients/ios` builds with rust-overlay's Apple
  targets and the terminal client with nixpkgs' Rust, and a desktop shell
  on a webview toolkit needs WebKitGTK on Linux. A workspace resolves one
  lock for all of them, so each program's dependency tree would follow the
  others'.
- **Nix builds vendor a lock.** A program packaged with Nix vendors its
  dependencies from its `Cargo.lock`. One lock for every crate would mean
  another shell's dependency update changes the terminal client's hash and
  rebuilds it.
- **Profiles belong to the root.** Cargo reads `[profile.*]` only from the
  workspace root. A size-tuned release profile for one shell would apply to
  every member, or move to flags.
- **Upgrades stay local.** A dependency bump for one program does not move
  another until someone chooses to.

The cost is accepted: a shared crate compiles once per program, a shared
dependency can sit at different versions in different locks, and there is
no single `cargo test`. CI runs each crate in its own devenv.

### Alternatives considered

- **A port per shell, locked only by fixtures.** Rejected for this client set.
  The fixtures stay, as the check between Elixir and the library. They are not
  a reason to write the engine four times.
- **Kotlin Multiplatform.** Rejected. It has the best shared SQL tooling, and
  no boundary on Android, but a terminal UI or a non-Kotlin desktop window
  would be hosting the Kotlin runtime. The iOS widget would carry that runtime
  too.
- **Swift as the shared library.** Rejected. iOS would be native, and every
  other shell would call Swift from outside. That fits a phone-first product,
  not peer clients.
- **A shared UI toolkit** (GPUI, Qt, Flutter, Compose). Rejected. iOS still
  wants SwiftUI, a widget, and App Intents. The desktop toolkit stays an open
  choice.
- **C++.** Rejected. It links everywhere, and it is the wrong language for the
  merge rules.

## Consequences

- Do not create `sync/core`, `sync/fixtures`, or `clients/` until that work
  starts. The pull endpoint, the `resolved_at` skew clamp, and `discarded_at`
  on project folders still come before the crate (ADR 0014).
- Shared fixtures are written for two runners, Elixir and Rust, not for
  every shell.
- When the crate exists, its toolchain is not a root `devenv.nix` that wraps
  `web/` (ADR 0015).
- A change to `clients/shell-common` is a change to every shell that uses
  it: run their tests too. Keychain service names and token paths are part
  of a shell's contract; changing one signs its users out.
- Library tests cover the client rules against those fixtures: dirty-field
  pull merge, discard, `resolved_at`, a rank between two neighbors, and link
  ids.
- The web app stays online. It does not gain an offline cache (ADR 0014).
- Versions stay independent. The library has its own version. An App Store
  build number is still not a git tag.
