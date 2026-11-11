# marskal

Marskal tasks from the terminal, for people and for agents (ADR 0020). It
links the local replica in `core/replica` and keeps a copy of your tasks,
so it works offline and syncs when it can.

```sh
devenv shell        # Rust toolchain
cargo build --release
```

The devenv shell sets `MARSKAL_SERVER` to the local web app,
http://marskal.localhost:8275 (`devenv up` in `web/`). Inside it, any
`marskal` talks to that server unless you give `--server`.

## Installing with Nix

The flake here builds `marskal` for Linux (x86_64, aarch64) and Apple
Silicon macOS, and has a Home Manager module for both:

```nix
inputs.marskal-terminal.url = "git+https://…/marskal?dir=clients/terminal";

# in a Home Manager configuration
imports = [ inputs.marskal-terminal.homeModules.default ];
programs.marskal = {
  enable = true;
  settings.server = "https://tasks.marskal.example";  # config.toml
  # keychain = false;  # headless: tokens in a file
};
```

Then sign in once with `marskal login`. To install the package alone, use
`packages.${system}.default`.

## Signing in

```sh
marskal login --server https://tasks.marskal.example
```

`login` shows a code and opens the browser, where you confirm the code,
name the device, and allow it, signed in to the web app. The server's OAuth
is Ory Hydra (ADR 0021); `marskal` finds it from the server's metadata, so
only the server's URL is configured. `--read-only` asks for read access
only. `--no-browser` only prints the link. `logout` signs the device out on
the server; `logout --forget` also deletes the local data. Settings in the
web app lists devices and signs them out too.

## Commands

| Command | Does |
|---------|------|
| `add <title> [--project P \| --no-project \| --inbox] [--parent T] [--planned D] [--due D] [--defer D \| --defer-indefinitely] [--tag T]… [--note N]` | Capture; the inbox by default |
| `ls [--inbox \| --project P \| --tag T \| --everything] [--all]` | The open stream by default; `--all` adds deferred and unavailable tasks |
| `show <task>` | One task |
| `done`, `drop`, `reopen <task>…` | Change state |
| `edit <task> [--title] [--note \| --no-note] [--planned \| --no-planned] [--due \| --no-due] [--defer \| --defer-indefinitely \| --no-defer] [--parent T \| --no-parent]` | Change fields |
| `move <task> --project P \| --no-project \| --inbox` | Move, subtasks along |
| `rm <task>…` | Delete, subtasks too |
| `tag`, `untag <task> <tag>` | Tags |
| `projects [add <title> \| done \| drop \| reopen <project>]` | Projects |
| `tags [add <name> [--parent T]]` | Tags |
| `sync`, `status`, `rejections` | Sync state |

A task is named by its short id (the eight characters `ls` shows), any
unique start or end of its id, or the full id. A project by id or title; a
tag by id, name, or path (`Home/Errands`). Days are `today`, `tomorrow`, a
weekday (`fri`: the next one), `+3d`, `+2w`, or `2026-10-05`, optionally
with a time (`fri 14:00`), in this machine's timezone. A day without a time
takes the field's default: Defer 00:00, Planned 09:00, Due 17:00.

Writes are queued locally and work offline; a write then syncs. A read
syncs first when the last sync is over a minute old. If the network fails
there, the command still works on local data and notes that it did not
sync. `--offline` skips the network.

## Files

XDG base directories, on macOS too:

| Path | Holds |
|------|-------|
| `$XDG_CONFIG_HOME/marskal/config.toml` | Your settings: `server`. Optional; `marskal` never writes it |
| `$XDG_DATA_HOME/marskal/<server>.db` | The local database and its outbox of unsent edits |
| `$XDG_STATE_HOME/marskal/state.toml` | The server last signed in to |
| `$XDG_STATE_HOME/marskal/` | The refresh lock; the token file where there is no keychain |

The server is `--server` (or `MARSKAL_SERVER`), else `server` in
config.toml, else the one last signed in to. `login` says so when a
setting will send later commands elsewhere.

Tokens go to the OS keychain. `MARSKAL_NO_KEYCHAIN=1` keeps them in the
token file (mode 0600) instead. `marskal` creates `$XDG_DATA_HOME/marskal`
as mode 0700. `MARSKAL_SERVER` and `MARSKAL_DB` set
`--server` and `--db`.

## For agents: `--json`

Every command takes `--json` and prints one JSON object on stdout. The
shape is version 1 and changes only with that number.

- Every object has `"version": 1`. Results of commands that may sync have
  `"synced"`, and `"sync_error"` when it is false.
- Tasks are sync API rows (ADR 0019) plus what the engine derives:
  `project` (title), `depth`, `tags` (`[{id, path}]`), `effective` (the
  dates it goes by), `deferred`, `overdue`, `available`, `resolved`.
- `ls` → `{"tasks": [...]}`; `add`, `show`, `edit`, `move`, `tag` →
  `{"task": {...}}`; `done`, `drop`, `reopen`, `rm`, `projects add`,
  `tags add` → `{"action", "ids"}`; `projects` → `{"projects"}`; `tags` →
  `{"tags"}`; `status`, `sync`, `rejections` → their fields.
- An error is `{"version": 1, "error": {"code", "message"}}` with a
  non-zero exit: 2 usage, 3 not found or ambiguous, 4 not signed in or not
  allowed, 5 network, 1 anything else.
