# 0008. Task and project states

## Status

Accepted

## Context

Tasks and projects need explicit lifecycles. Recurrence (ADR 0007) needs clear
terminal states for “resolved” instances. Parking work (including open-ended pause)
belongs in **Defer** (ADR 0006), including an **indefinite** defer option — not a
separate **On Hold** state on either entity.

## Decision

### Shared lifecycle (tasks and projects)

Every **task** and every **project** has exactly one of three states:

| State | Meaning |
|--------|---------|
| **To-Do** | Open (subject to Defer/Planned/Due — ADR 0006). |
| **Done** | Finished successfully / outcome achieved. Terminal for this entity (or task instance). |
| **Dropped** | Will not do / abandoned. Terminal. |

- Default for new tasks and projects: **To-Do**.
- **Done** and **Dropped** are terminal; retained in history by default.
- **No On Hold** on tasks or projects.
- To pause without a resume date: **Defer → Indefinite** (ADR 0006). To pause until a
  time: **Defer → until datetime**. Clear defer (or let a until-time pass) to surface again.
- List defaults: open **To-Do**, respecting Defer. Done/Dropped in history-style views
  unless filtered in.
- No separate “Skipped” state — **Dropped** covers skip (recurring and one-off tasks).
- Project state is independent of task states on its actions (a To-Do project can have
  Done tasks).
- Stalled detection (e.g. no next action) applies to **To-Do** projects that are **not**
  currently deferred (including not indefinitely deferred).

### Recurrence (tasks only; see ADR 0007)

For **on completion** mode, **Done** and **Dropped** both **resolve** the current
occurrence and each **generates the next** (until end date/count). **To-Do** does not.

**Regular** mode schedules regardless; Done/Dropped only close that instance.

**Count** = N **generated** instances, not N Dones.

### Non-goals

- On Hold state (use Defer, including indefinite).
- Separate “Skipped” state.
- Soft-delete as a substitute for Dropped.
- Custom status pipelines / arbitrary workflows.

## Consequences

- Task and project schema: the **same three-value** state enum/check constraint.
- UI: complete → Done, drop → Dropped; pause via Defer (until / indefinite), not a
  fourth status.
- Simpler mental model: state = open vs finished vs abandoned; timing/visibility = dates.
- Tests: state transitions; on-completion spawns on Done and Dropped; indefinite and
  until-defer hide without state change.
