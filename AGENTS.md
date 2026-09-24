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
| Import framework | [0013](docs/adr/0013-import-framework.md) |
| Sync, offline clients | [0014](docs/adr/0014-offline-sync.md) |
| Repository layout | [0015](docs/adr/0015-repository-layout.md) |

---

## Vocabulary

| Term | Meaning |
|------|---------|
| **Task** | Code/model name for captured work (`tasks` table) — ADR 0010 |
| **Inbox** | Unclarified tasks (`inbox = true`) — only special placement flag |
| **Open tasks** | Default engage stream: `state = to_do`, `inbox = false` (not deferred when dates exist) |
| **Project** | Outcome needing more than one action; **not** nestable under other projects |
| **Project folder** | Nestable container for projects; **name** only + **Active/Dropped**; **share unit** later — ADR 0003, 0009 |
| **Tag** | Nested label on tasks/projects; project tags **inherit** to tasks (ADR 0005) |
| **Waiting / Someday** | User **tag** conventions (not schema lists) — Phase 2+ |
| **Series / occurrence** | Recurrence rule vs single instance (regular or on-completion mode) |
| **To-Do** | Open (default for tasks and projects) |
| **Done** | Terminal: finished / outcome achieved |
| **Dropped** | Terminal: will not do / abandoned (task “skip”; also one-off cancel) |
| **Defer** | On tasks & projects: **until** a datetime **or indefinite**; hidden by default; show-deferred toggle |
| **Planned** | On tasks & projects; agenda for that day; normal in open stream / other filters |
| **Due** | On tasks & projects; hard deadline; highlight/notify if open past due |

### Soft-GTD flow

1. Capture → Inbox (`inbox = true`)  
2. Clarify → leave inbox (`inbox = false`); drop, tag, project, dates as needed (later phases)  
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

**Inbox** (ADR 0010): boolean on tasks, orthogonal to state. New captures:
`inbox=true`, `state=to_do`. Clarify → `inbox=false`. **No** `list` column.
Default home: **Open tasks** stream. Timezone is stored per user, default
**Europe/Copenhagen** (ADR 0014).

### Recurrence (ADR 0007 — product differentiator)

- Model **series** vs **occurrence**; not only “next due.”
- **Mode:** **regular** (next on schedule even if previous open) or **on completion**.
- **On completion:** both **Done** and **Dropped** resolve the instance and **spawn next**
  (from resolution time + rule). To-Do does not.
- Anchor on **one of** Defer / Planned / Due; that field is what the rule advances.
- **Interval** = number + frequency: minutes | hours | days | weeks | months | years.
- **Weekly:** optional weekday set. **Monthly:** day-of-month (incl. last) and/or
  nth weekday (1st–5th/last × Mon–Sun | work day | weekend day).
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
- Project dates do not auto-rewrite child task date columns (default).

### Structure (ADR 0009)

```text
Project folders (nested) → Project (flat) → Tasks (nested outliner)
```

- **Tasks:** parent/child tree; outliner UX (indent, collapse, sibling order).
- **Projects:** never nested under projects.
- **Project folders:** nested; **name** + **Active | Dropped** only (no Done/dates).
  Projects optionally filed in one folder; drop folder does not resolve projects.
- **Sharing (later):** share a **folder** → that folder + subfolders + projects (+ tasks).
- Subtasks are full tasks; parent Done/Dropped does not auto-resolve children by default.

### Tags (ADR 0005, Phase 2+)

- Nested tags on **tasks** and **projects**.
- **Effective task tags** = task tags ∪ **project tags** (inheritance at read/filter time).
- No `ltree`; `parent_id` + `parent_path text[]` (see ADR).

---

## Phases

Build in order; keep each shippable.

| Phase | Deliver |
|-------|---------|
| **0 Foundation** | Rails + devenv Postgres; layout; **Rails auth** (`generate authentication`); `user_id` on personal models |
| **1 Capture & clarify** | Task model; **inbox** boolean; **open tasks** stream; states (To-Do / Done / Dropped) |
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
- Do not add a root `devenv.nix`. Do not create `clients/ios/` or
  `sync/fixtures/` until that work starts.

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
- **Import (ADR 0013):** not ported yet. When it is, adapters parse to an
  `Imports.Graph`; file upload now, OAuth is a future fetcher. First source:
  OmniFocus backup. Park unmapped fields on `import_items.extras`. Skip existing
  `(user, source, source_id)` on re-import. Do not add competing-app libraries.
- **UI (ADR 0012, ADR 0016):** HEEx function components plus plain CSS `@scope`.
  No Tailwind, no daisyUI, no UI kit. Tokens stay on `:root`.
- **Icons:** the `lucide_icons` package. Use `<Lucideicons.inbox class="icon" />`.
  Do not inline SVG paths, do not clone the icon repo, and do not add Heroicons.

### Auth & tenancy

- Email + password sessions via `phx.gen.auth` (ADR 0003, ADR 0016). Always
  scope personal data by the current user. Magic link is not the way in.
- Owner-only until sharing; then **folder_memberships** + ancestor cascade (not
  per-project membership as primary). No personal-org multi-DB tenancy.

### Tags (Phase 2+)

- Per ADR 0005: `name`, `parent_id`, `parent_path text[]`; task↔tag and project↔tag;
  effective task tags include project tags; no `ltree`; HTML breadcrumbs; Unicode/emoji OK.

### Hosting

- Local = dev only. Production = VPS (Nix-oriented). Env-based secrets (ADR 0004).

### Quality

- Prefer explicit state fields. UTC storage; display in user zone (default zone OK early).
- Task and project state: same **3** values (ADR 0008); **Defer** (until | indefinite) /
  Planned / Due on both (ADR 0006).
- Structure: `tasks.parent_id`, `project_folders` tree, `projects.project_folder_id`;
  no project-to-project parent (ADR 0009). Prevent parent cycles.
- Done/Dropped retained in history by default (not deleted). Synced domain rows
  are discarded with a tombstone, not hard-deleted (ADR 0014).
- **Sync (ADR 0014):** writes are field patches with a command id, appended to a
  server change feed. Clients may supply UUIDv7 ids. Task sibling order is a
  fractional rank. Do not sync derived fields (`parent_path`, effective tags).
  Recurrence spawning is a pure function; rule-created occurrence ids are
  UUIDv5 from the series id and the anchor. The web app stays online — no
  browser offline cache. Writes go through `Marskal.Changes.apply/4`; a patch
  with no changes appends nothing. Not built yet, and due before the first
  sync client: `discarded_at`, `resolved_at`, sibling rank, the pull endpoint.
- Tests: state transitions; user isolation; defer/planned/due; outliner/folder structure;
  **recurrence** matrix (ADR 0007); tag inheritance in Phase 2+; sync merge,
  command replay, tombstones, and occurrence-id vectors (ADR 0014).

### Agent behavior

- Update `devenv.nix` when tooling changes.
- Prefer vertical slices; ask before large scope expansions.
- Significant architecture choices → new/updated **ADR**, not a novel in this file.
- Default: **devenv + Bundler + soft-GTD (inbox + open stream) + recurrence + planning**;
  tags from Phase 2.

---

## Open decisions

Resolve with the user when blocking; then prefer an ADR (or a short note here).

- [ ] VPS provider / NixOS vs Nix-on-distro (when deploy starts)
- [ ] Shared work: open tasks from shared projects on personal open stream vs only under
      shared folder/project views
- [ ] Sharing roles (viewer/editor) and re-share rules
