# 0006. Defer, Planned, and Due (tasks and projects)

## Status

Accepted

## Context

Work items need more than a single “date” field. Soft-GTD and planning distinguish:

- “Don’t bother me about this until …” (or “until I say otherwise”)
- “I intend to work on this on …”
- “This really must be finished by …”

A single due date collapses those meanings. The same three fields apply to **tasks**
and **projects**. Open-ended pause was considered as a separate **On Hold** state;
that is rejected in favor of **Defer** with an **indefinite** option (ADR 0008).

## Decision

Each **task** and each **project** may set **Defer**, **Planned**, and/or **Due**.
Store instants as timestamptz (UTC); display in the user’s zone.

| Field | Intent | Surfacing |
|--------|--------|-----------|
| **Defer** | Quiet until a condition clears | **Hidden by default** while deferred. Reveal with **“Show deferred …”**. Does not by itself put the item on an agenda. |
| **Planned** | Intentional focus for a calendar day | On the **agenda for that day**; still visible in the open stream and other filters (subject to Defer). |
| **Due** | Hard commitment by this instant | On the **agenda for that day**, apart from Planned; today's also lists what is overdue. Highlight / urgency when approaching or past due and still open; notifications when not done (mechanism later). |

### Defer shapes

Defer is optional and is either:

| Shape | Behavior |
|--------|----------|
| **Until** | A specific date/time. Still deferred while `now < defer_until`. After that, not deferred. |
| **Indefinite** | No end time. Stays deferred until the user **clears** defer (or changes to an until-time). Same hide/show rules as until-defer. |

- **Indefinite** replaces a separate On Hold state for both tasks and projects.
- UI: pick “defer until …” or “defer indefinitely” (wording flexible).
- Schema sketch (illustrative): e.g. `defer_until timestamptz NULL` plus
  `deferred_indefinitely boolean NOT NULL DEFAULT false`, with a check constraint that
  indefinite ⇒ `defer_until` IS NULL (or equivalent single discriminated representation).
  Exact columns are implementation detail; semantics are not.
- “Still deferred” predicate: `deferred_indefinitely OR (defer_until IS NOT NULL AND now < defer_until)`.

### Rules of thumb

- Same field semantics on **tasks** and **projects**.
- Fields are **independent**: any combination (including none).
- **Inbox** capture should not require any of them.
- **Planned** and **Due** drive agenda membership (not a plan join table for MVP).
- **Due** ≠ Planned; **Defer** ≠ Due.
- Task and project dates are **independent** by default (no auto-cascade of project
  dates onto child task columns). Open-stream / filter logic may optionally hide tasks
  whose **project** is still deferred — define clearly in implementation.
- Recurring occurrences use these fields per occurrence where relevant (ADR 0007).

### Deferred visibility (decided)

- **Default:** exclude still-deferred tasks from the open stream and normal filters
  (until **or** indefinite).
- **Opt-in:** **“Show deferred tasks”** (and the same idea for projects).
- Prefer per-view/session toggles.

### Non-goals (this ADR)

- On Hold lifecycle state (ADR 0008).
- Full calendar / time-blocking product.
- Exact notification channels for Due.
- Automatic cascade of project dates onto task date columns.

## Consequences

- Schema: Planned and Due as nullable timestamptz on tasks and projects; Defer as
  until and/or indefinite as above — not one overloaded `due_on`.
- Open stream and other task queries use the “still deferred” predicate; honor
  show-deferred.
- Agenda keys off **Planned** and **Due**.
- UI teaches three dates; indefinite is a Defer option, not a fourth status chip.

## Implementation notes (2026-09-28)

- Columns: `defer_until`, `deferred_indefinitely` (check: not both),
  `planned_at`, `due_at`, all `timestamptz`. A Defer change patches both
  Defer columns, so offline edits merge into one shape (ADR 0014).
- Indefinite is a boolean, not `defer_until = 'infinity'`. Infinity needs
  Postgrex's `allow_infinite_timestamps`, a custom Ecto type for `:inf`, a
  JSON sentinel every sync client must agree on, and a guard in recurrence
  anchor math. The explicit field costs one extra column.
- People pick a day and an optional time on their stored zone's clock. A day
  with no time takes the field's default: Defer 00:00, Planned 09:00, Due
  17:00.
- A task in a still-deferred project counts as deferred.
- Deferred follows the tag-unavailable rule (ADR 0005): the open stream and
  the agenda hide both behind one "Show unavailable" toggle; project, tag,
  and inbox views show the task with a mark.
- The agenda for today also lists to-do tasks planned on earlier days, so a
  missed plan stays visible.
- The agenda lists Due beside Planned (2026-10-13): what is due that day,
  and for today what is overdue too. A task both due and planned shows
  once, under Due. Due is the firmer of the two, so this does not make
  Planned and Due the same thing.
- Dates inherit down the outline (2026-09-29, with ADR 0009 nesting). A task
  with no Planned or Due of its own goes by its nearest ancestor task's, then
  its project's; the agenda and the Due marks use that. A task is deferred
  while it, any ancestor, or its project is, so an earlier Defer on a subtask
  does not surface it before its parent. Inherited dates are derived at read
  time, not written, and rows mark them as inherited.
