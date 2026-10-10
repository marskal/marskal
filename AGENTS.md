# Marskal Tasks — agent rules

Personal task/todo manager: **recurring tasks**, **soft-GTD**, **planning**.
**PostgreSQL** (single DB), **devenv** locally, **VPS/Nix** in production.
The web app in `web/` is **Phoenix + LiveView** (ADR 0016): Elixir 1.20,
Erlang/OTP 29, Bandit, Ecto, Postgres 18.

This file is **short and actionable**. Rationale and history live in
**[docs/adr/](docs/adr/)** — follow accepted ADRs; don’t re-litigate them in code.

| Topic | ADR |
|--------|-----|
| ADRs as process | [0001](docs/adr/0001-record-architecture-decisions.md) |
| Postgres, single DB | [0002](docs/adr/0002-single-postgres-database.md) |
| Auth, multi-user, sharing | [0003](docs/adr/0003-rails-auth-and-sharing.md) |
| Hosting | [0004](docs/adr/0004-hosting-vps-nix.md) |
| Soft-GTD, nested tags | [0005](docs/adr/0005-soft-gtd-nested-tags.md) |
| Defer / Planned / Due | [0006](docs/adr/0006-task-defer-planned-due.md) |
| Recurrence | [0007](docs/adr/0007-recurrence.md) |
| Task & project states | [0008](docs/adr/0008-task-states.md) |
| Structure (outliner / folders) | [0009](docs/adr/0009-structure-outliner-and-folders.md) |
| Task model, inbox, Phase 1 | [0010](docs/adr/0010-task-lists-and-phase1-defaults.md) |
| UUIDv7 primary keys | [0011](docs/adr/0011-uuidv7-primary-keys.md) |
| ViewComponent + `@scope` CSS | [0012](docs/adr/0012-viewcomponent-scoped-css.md) |
| Web stack (Phoenix, at the port) | [0016](docs/adr/0016-elixir-phoenix-web.md) |
| Inbox as a location | [0017](docs/adr/0017-inbox-location.md) |
| Import framework | [0013](docs/adr/0013-import-framework.md) |
| Sync, offline clients | [0014](docs/adr/0014-offline-sync.md) |
| Client sync library (Rust) | [0018](docs/adr/0018-rust-client-sync-library.md) |
| Sync API, OAuth sign-in | [0019](docs/adr/0019-sync-api-and-oauth-sign-in.md) |
| Terminal client (`marskal`) | [0020](docs/adr/0020-terminal-client.md) |
| OAuth server (Ory Hydra) | [0021](docs/adr/0021-ory-hydra-authorization-server.md) |
| URL on tasks & projects | [0022](docs/adr/0022-task-and-project-url.md) |
| User preferences | [0023](docs/adr/0023-user-preferences.md) |
| Thunderbird extension | [0024](docs/adr/0024-thunderbird-extension.md) |
| Flagged tasks & projects | [0025](docs/adr/0025-flagged.md) |
| Repository layout | [0015](docs/adr/0015-repository-layout.md) |

---

## Vocabulary

| Term | Meaning |
|------|---------|
| **Task** | Code/model name for captured work (`tasks` table) — ADR 0010 |
| **Inbox** | A location beside **No project** and each project (`inbox = true`, no project) — ADR 0017 |
| **Open tasks** | Default engage stream: `state = to_do`, `inbox = false`, not under a resolved task or project (not deferred when dates exist) |
| **Project** | Outcome needing more than one action; **not** nestable under other projects |
| **Project folder** | Nestable container for projects; **name** only + **Active/Dropped**; **share unit** later — ADR 0003, 0009 |
| **Tag** | Nested label on tasks/projects; project tags **inherit** to tasks (ADR 0005) |
| **Waiting / Someday** | User **tag** conventions (not schema lists) — Phase 2+ |
| **Series / occurrence** | Recurrence rule vs single instance (regular or on-completion mode) |
| **Repeat** | The UI's word for recurrence ("Repeats weekly", Repeat, Stop). Code, schema, and sync keep *recurrence*, *series*, *occurrence* |
| **To-Do** | Open (default for tasks and projects) |
| **Done** | Terminal: finished / outcome achieved |
| **Dropped** | Terminal: will not do / abandoned (task “skip”; also one-off cancel) |
| **Defer** | On tasks & projects: **until** a datetime **or indefinite**; hidden by default; show-deferred toggle |
| **Planned** | On tasks & projects; agenda for that day; normal in open stream / other filters |
| **Due** | On tasks & projects; hard deadline; highlight/notify if open past due |

### Soft-GTD flow

1. Capture → Inbox (`inbox = true`)  
2. Move → a project or **No project** (leaves the inbox); tag, drop, dates as needed  
3. Organize → projects, dates, tags (tags/projects from Phase 2)  
4. Reflect → weekly review support  
5. Engage → open stream + plan + tag/project filters + dues  

Do not reintroduce a multi-list enum (next/waiting/someday/reference). Do not treat
every item as a calendar event. Do not implement a first-class **Context** model —
use **tags** (ADR 0005). Detailed task audit history is a separate future concern
(ADR 0010), not list placement.

### Task & project states (ADR 0008)

**Tasks and projects** share three states: **To-Do** | **Done** | **Dropped**.  
No On Hold, no Skip (**Dropped**). Pause with **Defer** (until or **indefinite**).

**Inbox** (ADR 0010, 0017): a task's location is Inbox | No project | a
project; `CHECK (NOT inbox OR project_id IS NULL)`. One picker moves a task,
and a move patches `inbox` and `project_id` together. Tags do not affect it.
New captures: `inbox=true`, `state=to_do`. No Clarify action. **No** `list` column.
Default home: **Open tasks** stream. Timezone is stored per user, default
**Europe/Copenhagen** (ADR 0014), in `user_preferences` (ADR 0023).

### Recurrence (ADR 0007 — product differentiator)

- Model **series** vs **occurrence**; not only “next due.” `recurrence_series` holds
  the rule and `kind` (task | project). Occurrences are tasks or projects with
  `series_id` and an immutable `occurrence_for`. A project's next copies its live tasks.
- The next occurrence copies the latest (the live one created last): title, notes,
  URL, flag, location, parent, tags, and its live subtasks, every one To-Do.
  Other dates, subtasks' too, keep their offset from the anchor on the user's zone clock.
- Occurrences are the history; no completions table. A generated id that exists,
  discarded or not, is never created again.
- The server creates every occurrence after the first; a client only joins a task
  or project as a series' first. Reopening an occurrence keeps the one its completion made.
- One occurrence at a time: resolving the latest (Done or Dropped) creates the
  next, in that command. **Mode:** **regular** (the slot after the one resolved,
  or the first after the resolution when that has passed, skipping those
  between) or **on completion** (`interval` after the resolution). Deleting
  the latest ends the series; Dropped skips one.
- **On completion:** both **Done** and **Dropped** resolve the instance and **spawn next**
  (`interval` after the resolution time, clamped to a short month's last day;
  no day limits yet). To-Do does not.
- Anchor on **one of** Defer / Planned / Due; that field is what the rule advances.
- **Interval** = number + frequency: minutes | hours | days | weeks | months | years.
- **Weekly:** optional weekday set; the week starts on the series' `week_start`,
  copied from the user's preference when the series is made. **Monthly / yearly:**
  rows in `on_days`, a day of the month (1–31, or 1st–5th from the end) or an nth
  Mon–Sun (1st–5th), work day (1st–23rd), or weekend day (1st–10th), also
  1st–5th from the end; a yearly row also names its month. A month's
  rows are one set of days. Regular mode only; it expands as RFC 5545 does, so a day
  the month lacks is skipped; see ADR 0007.
- **End:** none, **end date**, **count = N generated** (not N Dones), or both (whichever first).
- Structured rule storage (not RRULE-primary). Overdue open items stay visible.

### Dates & planning (ADR 0006)

**Tasks and projects** share three independent optional timestamps:

| Field | Surfacing |
|--------|-----------|
| **Defer** | **Until** datetime **or indefinite**; hidden while deferred; show-deferred reveals |
| **Planned** | On that day’s **agenda**; still normal in open stream / other filters |
| **Due** | Must-do-by; highlight + notifications if not done |

- Agenda driven by **Planned**. Inbox needs none of the three.
- **Indefinite defer** replaces On Hold for open-ended pause (tasks and projects).
- Dates are never copied down. A task with no Planned or Due goes by the nearest task
  above that has one, then its project; it is deferred while anything above it is
  (`Marskal.Tasks.EffectiveDates`, derived at read time).

### Structure (ADR 0009)

```text
Project folders (nested) → Project (flat) → Tasks (nested outliner)
```

- **Tasks:** parent/child tree; outliner UX (indent, collapse, sibling order).
- **Projects:** never nested under projects.
- **Project folders:** nested; **name** + **Active | Dropped** only (no Done/dates).
  Projects optionally filed in one folder; drop folder does not resolve projects.
- **Sharing (later):** share a **folder** → that folder + subfolders + projects (+ tasks).
- Subtasks are full tasks. A Done/Dropped parent task or project makes the tasks below it
  count as resolved (derived; their own state is not written). Reopening brings them back.

### Tags (ADR 0005, Phase 2+)

- Nested tags on **tasks** and **projects**.
- **Effective task tags** = task tags ∪ **project tags** (inheritance at read/filter time).
  Never from a parent task.
- A tag matches its subtree. The tag view is an outline: the tag's own tasks, then one
  group per child tag.
- Tag states **Active | On Hold | Dropped**. An on-hold effective tag, or
  only dropped ones, makes a task **unavailable**. On Hold applies to that tag only;
  Dropped covers its subtree.
- No `ltree`; `parent_id` + `parent_path text[]` (see ADR).

---

## Phases

Build in order; keep each shippable.

| Phase | Deliver |
|-------|---------|
| **0 Foundation** | Rails + devenv Postgres; layout; **Rails auth** (`generate authentication`); `user_id` on personal models |
| **1 Capture & inbox** | Task model; **inbox** boolean; **open tasks** stream; states (To-Do / Done / Dropped) |
| **2 Projects, planning, tags** | Projects + **folders**; **task outliner**; dates/tags/inheritance; agenda; Waiting/Someday as tags |
| **3 Recurrence** | ADR 0007: mode, anchor, interval, limits, end date/count; Done/Dropped spawn rules |
| **4 Review & polish** | Weekly review; tag UX polish; empty states; keyboard-friendly capture |

Do not jump to Phase 3 chrome before Phases 1–2 capture/projects/tags are solid.
Recurrence schema may be designed early.

**Later (not Phases 1–3):** **folder sharing** (membership on folder; cascade to subtree) — ADR 0003.

---

## Engineering conventions

### Layout

The repository root is the product, not the web app (ADR 0015).

- **`web/`** — the Phoenix app. `devenv.nix` lives there. Run `devenv shell`
  and `devenv up` from `web/`. Paths in the Elixir section below are relative
  to it. Do not add a second app directory beside `web/`.
- **`docs/`** — ADRs, at the root.
- Do not add a root `devenv.nix`.
- **`sync/core/`** — the Rust client engine (ADR 0018): SQLite, outbox, pull
  merge, reads, and the operations every shell shares. `devenv shell` there
  for cargo. **`sync/fixtures/`** — vectors both Elixir and Rust run
  (`Marskal.SyncFixturesTest`, `tests/fixtures.rs`); regenerate from Elixir,
  never edit by hand.
- The first shell is `clients/terminal`: one `marskal` binary with subcommands,
  `--json` for agents, and later `marskal tui` (ADR 0020). XDG base
  directories on every platform, macOS included. Each Rust program
  has its own `devenv.nix`; no root Cargo workspace.
- Offline clients link one Rust library, `sync/core` (ADR 0018). Do not
  reimplement that engine in a shell. The Phoenix app does not call it.
- `clients/thunderbird` is capture only (ADR 0024): it pushes inbox inserts
  and never pulls, so it speaks the wire format itself. A client that shows
  or edits tasks links the library.

### Environment

- **devenv** for Elixir 1.20, OTP 29, libpq, and Postgres. No host Elixir.
- From `web/`: `devenv shell` before Mix work. Prefer editing `web/devenv.nix`
  over global installs. Do not float `pkgs.elixir`.
- Dev URL: **http://marskal.localhost:8275** (port **8275** ≈ TASK on phone keypad).
- **`devenv up`** (from `web/`) starts Postgres + Phoenix (`processes.server`).
  Postgres is that managed `services.postgres` process — never `pg_ctl start` /
  `start-postgres` against `web/.devenv/state/postgres` (it orphans a second cluster).

### Elixir

- **Phoenix via Mix** (`mix.exs` / `mix.lock`). Elixir **1.20**, OTP **29**,
  Phoenix **1.8**, LiveView **1.2**, Bandit.
- One app, modules `Marskal` and `MarskalWeb`. Not an umbrella.
- Domain writes go through context functions that append the change feed
  (ADR 0014). LiveViews do not save a whole row back.
- Domain primary keys are `uuid` with `DEFAULT uuidv7()`. A caller may supply
  the id. The change-feed cursor is `bigint GENERATED ALWAYS AS IDENTITY`.
- UI is HEEx function components. No Tailwind, no daisyUI. Tokens on `:root`,
  isolation with `@scope` (ADR 0012, ADR 0016).
- Login that ships is email + password, hashed with Argon2id. Do not present magic link as the way in.
- LiveDashboard is `/dev/dashboard`, and only a user with `superuser` set can open it.
- **PostgreSQL only**, single app DB (ADR 0002).
- **Lean into Postgres** (ADR 0002, **0011**): domain entity PKs default to
  **UUIDv7** (`uuid` + `DEFAULT uuidv7()`), not identity/`serial`. Other types
  are fine where they fit — a server-only counter is `GENERATED … AS IDENTITY`,
  not a sequence. Real **foreign keys**. DB constraints for real invariants.
  Extensions OK if in **nixpkgs** (enable in migrations + devenv as needed).
  Recency is `inserted_at`, not `id`.
- **Migrations are Ecto.** Enums, `uuidv7()` defaults, and identity columns are
  raw SQL in those migrations (ADR 0016).
- Server-rendered HEEx / LiveView unless an SPA is justified.
- Domain names match the vocabulary table. Schema via Ecto migrations only.
- **Import (ADR 0013):** adapters parse to an `Imports.Graph`. Fetchers
  acquire bytes: an OmniFocus backup upload, or Todoist OAuth (API v1 sync,
  `data:read`, token not stored). Parse and apply run as Oban jobs; the
  payload is held in `import_batches.payload` only until apply, failure, or
  expiry after 24 h. Park unmapped fields on `import_items.extras`; an item
  that loses something the user must fix gets an "Import problems" tag and a
  note block saying what (`Imports.Problems`). Re-import
  updates existing `(user, source, source_id)` items by a three-way merge
  against `import_items.fields`: the user's edits win, and an item the
  user deleted is imported again as a new record. A Todoist repeat in a form
  `Imports.TodoistRecurrence` reads makes the task a series' first occurrence;
  free-form repeats stay import problems. Do not add competing-app libraries.
- **UI (ADR 0012, ADR 0016):** HEEx function components plus plain CSS `@scope`.
  No Tailwind, no daisyUI, no UI kit. Tokens stay on `:root`.
- **Icons:** the `lucide_icons` package. Use `<Lucideicons.inbox class="icon" />`.
  Do not inline SVG paths, do not clone the icon repo, and do not add Heroicons.
- **JavaScript is TypeScript**, erasable syntax only (no enums, namespaces, or
  parameter properties), so stripping types gives runnable JS. Colocated hooks take `extension="ts"` and extend
  `ViewHook`. `mix assets.check` type-checks them (precommit runs it).
- **npm packages** go in `assets/package.json`. Do not vendor a published library.
  Hex JS packages (`phoenix`, `phoenix_live_view`) stay out of npm. For utilities
  reach for `es-toolkit` before writing helpers.

### Auth & tenancy

- Email + password sessions via `phx.gen.auth` (ADR 0003, ADR 0016). Always
  scope personal data by the current user. Magic link is not the way in.
- Owner-only until sharing; then **folder_memberships** + ancestor cascade (not
  per-project membership as primary). No personal-org multi-DB tenancy.

### Tags (Phase 2+)

- Per ADR 0005: `name` (citext, unique per parent among live tags), `parent_id`,
  `parent_path text[]`, `state`, `rank`, `merged_into_id`, `discarded_at`; no `ltree`;
  HTML breadcrumbs; Unicode/emoji OK, NFC.
- `task_tags` / `project_tags` are entities with owner and `discarded_at`. Their id is
  UUIDv5 of the pair; untag and re-tag toggle `discarded_at` on that row.
- Subtree filters expand descendant ids in app code, not via `parent_path`.
- Offline duplicate tags merge on sync via `merged_into_id` (ADR 0014).
- Any character may be in a tag name, `/` included. Show paths as segments with a
  `›` chevron element between them. Autocomplete matches a query both as a literal
  name and as a path split on `/ : › > \`.

### Hosting

- Local = dev only. Production = a NixOS host using `web/flake.nix`
  (`nixosModules.default`). Env-based secrets (ADR 0004).
- A `mix.lock` change needs a new `depsHash` in `web/nix/package.nix`. A dep that
  downloads binaries at compile time needs a Nix-side fetch (see mdex_native there).
  A `package-lock.json` change needs nothing there. The build installs only npm
  `dependencies`: whatever the bundle imports goes there, checkers in `devDependencies`.

### Quality

- Prefer explicit state fields. UTC storage; display in user zone (default zone OK early).
- Task and project state: same **3** values (ADR 0008); **Defer** (until | indefinite) /
  Planned / Due on both (ADR 0006).
- Tasks and projects have one optional `url` (ADR 0022). Titles stay plain
  text; an import moves a title's link there. `javascript:`, `data:` and
  `vbscript:` are refused.
- Tasks and projects have one `flagged` boolean (ADR 0025); no priority
  levels. A flagged project flags its tasks at read time, a parent task
  does not. Imports map their flag, star, pin, or top priority to it.
- Structure: `tasks.parent_id`, `project_folders` tree, `projects.project_folder_id`;
  no project-to-project parent (ADR 0009). Prevent parent cycles.
  A subtask lives where its parent does; a move to another location leaves the
  parent and takes the subtree along. The outline trigger checks both at commit.
- Done/Dropped retained in history by default (not deleted). Synced domain rows
  are discarded with a tombstone, not hard-deleted (ADR 0014).
- **Sync (ADR 0014):** writes are field patches with a command id, appended to a
  server change feed. Clients may supply UUIDv7 ids. Task sibling order is a
  fractional rank. Do not sync derived fields (`parent_path`, effective tags).
  Only the server spawns occurrences. `Marskal.Recurrence.Schedule` is the
  pure function of the rule, the instant it steps from, and the user's
  timezone; clients get occurrences on pull. Rule-created occurrence ids are
  UUIDv5 from the series id and the slot. The web app stays online — no
  browser offline cache. Writes go through `Marskal.Changes.apply/4`; a patch
  with no changes appends nothing. Offline clients share one Rust engine
  (ADR 0018) instead of porting it per shell.
- **Sync API (ADR 0019):** `/api/v1`, bearer tokens from Ory Hydra (ADR 0021).
  Do not write OAuth protocol code in the web app: Hydra runs it, and the web
  app is its login, consent, and device verification UI over the admin API,
  and introspects tokens. The admin port is never exposed. Scopes
  `offline_access`, `sync:read`, `sync:write`; one device per consent. Pull returns current rows after a cursor, or a snapshot. Push applies
  commands in order; each entity has an allow-list of client-writable fields
  (`client_fields/1` beside its changeset), dispatched by `Marskal.Sync.Push`. A rejected command is not retried.
- **Preferences (ADR 0023):** one `user_preferences` row per user, keyed by
  `user_id`, made by a trigger, synced as an entity whose id is the user id.
  One typed column per preference. Read with `Accounts.preferences/1`; do not
  add preference columns to `users`.
- Tests: state transitions; user isolation; defer/planned/due; outliner/folder structure;
  **recurrence** matrix (ADR 0007); tag inheritance in Phase 2+; sync merge,
  command replay, tombstones, and the shared fixture vectors (ADR 0014).

### Agent behavior

- Update `devenv.nix` when tooling changes.
- Prefer vertical slices; ask before large scope expansions.
- Significant architecture choices → new/updated **ADR**, not a novel in this file.
- Default: **devenv + Bundler + soft-GTD (inbox + open stream) + recurrence + planning**;
  tags from Phase 2.

---

## Open decisions

Resolve with the user when blocking; then prefer an ADR (or a short note here).

- [ ] Shared work: open tasks from shared projects on personal open stream vs only under
      shared folder/project views
- [ ] Sharing roles (viewer/editor) and re-share rules
- [ ] Tombstone and change-feed retention: purge window, and the snapshot
      fallback for clients behind it (ADR 0014)
