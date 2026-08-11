# 0010. Task lists and Phase 1 defaults

## Status

Accepted

## Context

Before implementation we need a clear model for soft-GTD list placement (orthogonal to
lifecycle **state**), a canonical model name, and a default timezone for date boundaries.

## Decision

### Model name

- Use **`Task`** as the ActiveRecord model for actionable/captured work (including inbox
  items). Prefer this over `Item` in code and schema (`tasks` table).
- Product copy may still say “item” informally; code uses Task.

### State vs list (orthogonal)

**State** (ADR 0008): `to_do` | `done` | `dropped`

**List** (placement after clarify):

| List | Meaning |
|------|---------|
| `inbox` | Unclarified capture |
| `next` | Next action (actionable now) |
| `waiting` | Waiting for someone/something |
| `someday` | Someday/maybe |
| `reference` | Not actionable; keep for lookup (lightweight; not a full notes app) |

- New captures default: `list = inbox`, `state = to_do`.
- Clarify changes **list** (and may set project, dates later); does not invent extra states.
- Tasks in a **project** still have a list value (often `next` or `waiting`); project
  membership is `project_id`, not a list enum value.
- Done/Dropped are **state**; list may remain for history filters but primary open lists
  show `state = to_do` (and not deferred).

### Phase 1 minimum fields (tasks)

- `user_id`, `title`, `state`, `list`, timestamps
- Optional `notes` (text) — include from the start (cheap, useful)
- `parent_id` / outliner, dates, tags, recurrence: later phases per roadmap

### Time zone

- Store timestamps in UTC.
- **Default app timezone:** `Europe/Copenhagen` until per-user timezone settings exist.
- Day boundaries for Planned/agenda use the effective zone (default above for v1).

## Consequences

- Schema: `tasks.list` and `tasks.state` as Postgres enums or check-constrained text.
- Phase 1 UI: Inbox + list views + state transitions; no tags/outliner required yet.
- Vocabulary “Item” in AGENTS maps to **Task** in code.
