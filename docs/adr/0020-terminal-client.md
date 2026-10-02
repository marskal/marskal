# 0020. Terminal client

## Status

Accepted

The first offline client of [ADR 0018](0018-rust-client-sync-library.md).
Amends its `clients/tui` to one shell, `clients/terminal`, holding both the
command line and the terminal UI.

## Context

The first offline client is a terminal one: a command line for quick capture
and for scripts and agents, and later a full-screen terminal UI. Both need
the local database, the outbox, and the merge, which ADR 0018 puts in
`sync/core`.

They could be two programs linking the same library and opening the same
database file. They would still each need sign-in, the token store, the
server URL, the sync loop, and the HTTP client. That shared part is most of a
shell.

Agents run commands and parse what they print. Text meant for a person
changes with taste. An agent needs output that does not.

Alternatives considered:

- **Two binaries**, `clients/cli` and `clients/tui`. Rejected. Two copies of
  the shell around one library, and two things to install and sign in.
- **An MCP server as the agent bridge.** Deferred, not rejected. A command
  with `--json` serves any agent that can run a program. An MCP mode can be
  added later as a subcommand over the same code.

## Decision

One Rust program, **`marskal`**, in `clients/terminal`. It links `sync/core`
in-process, by path. There is no root Cargo workspace.

- **Subcommands** for capture and scripting: `login`, `logout`, `sync`,
  `add`, `ls`, `show`, `done`, `drop`, `move`, `edit`. Names follow the
  vocabulary in `AGENTS.md`.
- **`marskal tui`** opens the terminal UI. Built later, in the same program.
- **`--json` on every command.** The output is a documented, versioned shape:
  the same values as the sync API (ADR 0019), plus the derived fields the
  library computes. Errors in JSON mode are a JSON object on stdout and a
  non-zero exit code. Without `--json`, output is for people and may change.
- **Ids.** Full UUIDs in JSON. People may type a unique prefix, as with git.

### Local data

- Files follow the **XDG Base Directory** spec on every platform, macOS
  included. No `~/Library/Application Support`, and no `~/.marskal`. An unset
  or relative variable falls back to the spec's default.

  | What | Where | Default |
  |------|-------|---------|
  | Settings (server URL, output defaults) | `$XDG_CONFIG_HOME/marskal/config.toml` | `~/.config` |
  | Local database | `$XDG_DATA_HOME/marskal/` | `~/.local/share` |
  | Token file, logs | `$XDG_STATE_HOME/marskal/` | `~/.local/state` |

  The database is data, not cache: its outbox holds edits the server has not
  seen. The token file is state, not config, so a dotfiles repository that
  carries `~/.config` does not carry the secret. Nothing is written to config.
- One SQLite database per server and account. `--db` overrides its path.
- The database is in WAL mode. The command line and an open terminal UI use
  the same file at once. The library takes the write lock per command. The
  UI notices another process's writes and redraws.
- The refresh token is kept in the OS keychain. Where there is none (a
  headless server, a container), it is kept in a file readable only by the
  user, in the state directory. The access token is stored beside it until it
  expires, so a short command does not refresh.
- The command line and the terminal UI share one grant, so they share its
  refresh token. Refresh rotates it (ADR 0019), and two processes refreshing
  at once would look like reuse and revoke the grant. A process takes a lock
  file in the state directory, re-reads the stored token, and refreshes only
  if no one else just did.

### Sync

- Writes go to the outbox first and succeed offline.
- A command that writes then pushes and pulls. A command that reads pulls
  first when the last sync is older than one minute. A network failure there
  is not an error. The command works on local rows and reports that it did
  not sync.
- `--offline` skips the network. `marskal sync` does a push and a pull and
  fails if it cannot.

### Toolchain

`sync/core` and `clients/terminal` each have their own `devenv.nix` with the
Rust toolchain, as `web/` has its own (ADR 0015). Neither wraps another
program. A Nix package for `marskal` is added with the first release.

## Consequences

- `clients/terminal` and `sync/core` are created together, after the server
  endpoints of ADR 0019.
- The JSON shape is a contract. Changing it is a version bump of that shape,
  noted in the program's changelog.
- The terminal UI is a later step and does not block the command line.
- An MCP mode, if added, wraps the same commands. It does not get its own
  path to the database.
