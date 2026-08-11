# Marskal Tasks — agent rules

Personal task/todo manager: **recurring tasks**, **soft-GTD**, **planning**.
**Rails** + **PostgreSQL** (single DB), **devenv** locally, **VPS/Nix** in production.

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
| Task lists & Phase 1 defaults | [0010](docs/adr/0010-task-lists-and-phase1-defaults.md) |

---

## Vocabulary

| Term | Meaning |
|------|---------|
| **Task** | Code/model name for captured work (`tasks` table) — ADR 0010 |
| **Inbox** | Unclarified tasks (`list = inbox`) |
| **Next** | Next action list (`list = next`) |
| **Project** | Outcome needing more than one action; **not** nestable under other projects |
| **Project folder** | Nestable project container; **share unit** (subtree) later — ADR 0003, 0009 |
| **Tag** | Nested label on tasks/projects; project tags **inherit** to tasks (ADR 0005) |
| **Waiting** | `list = waiting` — blocked on someone/something |
| **Someday** | `list = someday` |
| **Reference** | `list = reference` — not actionable (not a full notes app) |
| **Series / occurrence** | Recurrence rule vs single instance (regular or on-completion mode) |
| **To-Do** | Open (default for tasks and projects) |
| **Done** | Terminal: finished / outcome achieved |
| **Dropped** | Terminal: will not do / abandoned (task “skip”; also one-off cancel) |
| **Defer** | On tasks & projects: **until** a datetime **or indefinite**; hidden by default; show-deferred toggle |
| **Planned** | On tasks & projects; agenda for that day; normal elsewhere |
| **Due** | On tasks & projects; hard deadline; highlight/notify if open past due |

### Soft-GTD flow

1. Capture → Inbox  
2. Clarify → trash / reference / someday / next / project (+ first next action)  
3. Organize → lists, projects, dates, tags (tags from Phase 2)  
4. Reflect → weekly review support  
5. Engage → plan + filters + dues  

Do not collapse inbox and next actions. Do not treat every item as a calendar event.
Do not implement a first-class **Context** model — use **tags** (ADR 0005).

### Task & project states (ADR 0008)

**Tasks and projects** share three states: **To-Do** | **Done** | **Dropped**.  
No On Hold, no Skip (**Dropped**). Pause with **Defer** (until or **indefinite**).

**Task list** (ADR 0010, orthogonal to state): `inbox` | `next` | `waiting` | `someday` | `reference`.  
New captures: `list=inbox`, `state=to_do`. Default timezone until per-user settings: **Europe/Copenhagen**.

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
| **Planned** | On that day’s **agenda**; still normal in other lists |
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
- **Project folders:** nested; projects optionally filed in one folder.
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
| **1 Capture & clarify** | Inbox; clarify → lists; **task states** (To-Do / Done / Dropped) |
| **2 Projects, planning, tags** | Projects + **folders**; **task outliner**; dates/tags/inheritance; agenda |
| **3 Recurrence** | ADR 0007: mode, anchor, interval, limits, end date/count; Done/Dropped spawn rules |
| **4 Review & polish** | Weekly review; tag UX polish; empty states; keyboard-friendly capture |

Do not jump to Phase 3 chrome before Phases 1–2 lists are solid. Recurrence schema may be designed early.

**Later (not Phases 1–3):** **folder sharing** (membership on folder; cascade to subtree) — ADR 0003.

---

## Engineering conventions

### Environment

- **devenv** for Ruby, Bundler, libpq, Postgres service. No host system Ruby/gems.
- `devenv shell` before Ruby/Rails work. Prefer editing `devenv.nix` over global installs.
- Dev URL: **http://marskal.localhost:8275** (`bin/dev`; port **8275** ≈ TASK on phone keypad).

### Rails

- **Rails only via Bundler** (`Gemfile` / `Gemfile.lock`). Currently **~> 8.1**.
- Do **not** add `pkgs.rubyPackages.rails` (or similar) to `devenv.nix` — nix Rails is
  older and fights the Gemfile on `GEM_PATH`.
- Do **not** use host or ad-hoc `gem install rails` for project work.
- Always **`bundle install`**, then **`bin/rails`** / **`bundle exec`**.
- devenv supplies Ruby + Bundler + Postgres tooling; the **app** supplies Rails.
- **PostgreSQL only**, single app DB (ADR 0002). Bundler owns `pg`.
- **Lean into Postgres** (ADR 0002): `IDENTITY` not `serial`; real **foreign keys**; DB
  constraints for real invariants; extensions OK if in **nixpkgs** (enable in migrations +
  devenv as needed).
- Hotwire (Turbo/Stimulus) / server-rendered HTML unless SPA is justified.
- Domain names match the vocabulary table. Schema via migrations only.

### Auth & tenancy

- Rails built-in auth from Phase 0 (ADR 0003). Always scope personal data by `current_user`.
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
- Done/Dropped retained in history by default (not deleted).
- Tests: state transitions; user isolation; defer/planned/due; outliner/folder structure;
  **recurrence** matrix (ADR 0007); tag inheritance in Phase 2+.

### Agent behavior

- Update `devenv.nix` when tooling changes.
- Prefer vertical slices; ask before large scope expansions.
- Significant architecture choices → new/updated **ADR**, not a novel in this file.
- Default: **devenv + Bundler + soft-GTD lists + recurrence + planning**; tags from Phase 2.

---

## Open decisions

Resolve with the user when blocking; then prefer an ADR (or a short note here).

- [ ] VPS provider / NixOS vs Nix-on-distro (when deploy starts)
- [ ] Shared work: next actions on personal Next vs only under shared folder/project views
- [ ] Sharing roles (viewer/editor) and re-share rules
