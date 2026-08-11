# 0010. Task model, inbox, and Phase 1 defaults

## Status

Accepted

## Context

Before implementation we need a clear model for capture/clarify, a canonical model
name, and a default timezone for date boundaries.

Earlier drafts treated soft-GTD **lists** (inbox / next / waiting / someday / reference)
as a first-class enum orthogonal to **state**. That overloads the task with a second
classification axis that largely duplicates **projects**, **tags**, and **dates**
(Defer / Planned / Due). Waiting and Someday are better as user tags; “next” is a
view of open work, not a bucket you file into.

## Decision

### Model name

- Use **`Task`** as the ActiveRecord model for actionable/captured work (including inbox
  items). Prefer this over `Item` in code and schema (`tasks` table).
- Product copy may still say “item” informally; code uses Task.

### No multi-list placement

- **Do not** store a `list` enum (`next` / `waiting` / `someday` / `reference`).
- Perspectives on tasks come from:
  - **Inbox** (boolean — see below)
  - **State** (ADR 0008)
  - **Projects** and **project folders** (ADR 0009; Phase 2)
  - **Tags** (ADR 0005; Phase 2) — including user conventions such as Waiting, Someday
  - **Defer / Planned / Due** (ADR 0006; Phase 2)

### Inbox (boolean)

- Tasks have **`inbox: boolean NOT NULL DEFAULT true`**.
- **Inbox** means unclarified capture — the only special placement field.
- New captures: `inbox = true`, `state = to_do`.
- **Clarify** sets `inbox = false` (and may later set project, tags, dates). Clarify does
  not invent extra states or list values.
- Inbox is **orthogonal to state**: a task can theoretically be done while still marked
  inbox, but normal UX clarifies before or as part of finishing; open views should not
  depend on that edge case.

### Default home and open stream

- **Default home (Phase 1+):** **Open tasks** — `state = to_do` and `inbox = false`
  (and, when dates exist, not still-deferred per ADR 0006).
- **Inbox** is a separate view for unclarified items (`inbox = true`, typically open).
- There is no first-class “Next” list; the open stream is the engage view.
- **Waiting** / **Someday** (and similar): **tags** when tags ship — not schema enums.
  Indefinite **Defer** remains the visibility pause (hide until cleared), distinct from
  a Someday *filter* via tag.

### State (unchanged; ADR 0008)

**State:** `to_do` | `done` | `dropped`

- Done/Dropped are lifecycle, not lists.
- Primary open views show `state = to_do` (and not deferred when dates exist).
- Done/Dropped rows are retained by default (not hard-deleted as the product concept).

### History

- **Detailed task history** (audit log of field changes, who/when clarified, etc.) is
  **out of scope** for this model and for Phase 1. If needed later, it is a **separate**
  concern (e.g. event/audit table), not list placement or overloaded state.
- Retaining Done/Dropped task rows is enough for basic “what did I finish?” — not a
  full history product.

### Phase 1 minimum fields (tasks)

- `user_id`, `title`, `state`, `inbox` (boolean), timestamps
- Optional `notes` (text) — include from the start (cheap, useful)
- `parent_id` / outliner, projects, dates, tags, recurrence: later phases per roadmap

### Time zone

- Store timestamps in UTC.
- **Default app timezone:** `Europe/Copenhagen` until per-user timezone settings exist.
- Day boundaries for Planned/agenda use the effective zone (default above for v1).

## Consequences

- Schema: `tasks.inbox boolean NOT NULL DEFAULT true`; `tasks.state` as Postgres enum or
  check-constrained text. **No** `tasks.list`.
- Phase 1 UI: capture → Inbox; clarify → leave inbox; default home = Open tasks stream;
  complete / drop. No multi-list nav.
- Phase 2+ filters (project, tag, agenda) replace classic GTD list chrome.
- Update product copy and AGENTS vocabulary: drop Next/Waiting/Someday/Reference as
  list enums; Waiting/Someday = tag conventions.
- Supersedes the earlier “state vs list orthogonal enums” decision in drafts of this ADR.
