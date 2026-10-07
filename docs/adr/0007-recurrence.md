# 0007. Recurrence (core differentiator)

## Status

Accepted; amended 2026-10-02 (projects, date offsets, open cap); amended 2026-10-07 (calendar expansion follows RFC 5545)

## Context

Recurrence is where Marskal Tasks should **shine**. Soft-GTD capture and
project/tag organization are table stakes; honest, flexible recurring work is not.
Recurrence must compose with the three surfacing timestamps from ADR 0006
(**Defer**, **Planned**, **Due**) rather than assuming a single “due date” model.

We prefer a **structured rule model** that matches the product UI (interval + unit +
optional weekly/monthly limiters). Full RRULE strings may be derived later for
interop, but are not the primary store.

## Decision

### Series vs occurrence

- A **series** holds the recurrence rule and stable identity.
- **Occurrences** are task instances with states from ADR 0008 (**To-Do**, **Done**,
  **Dropped** — tasks have no On Hold; use Defer to pause).
- Advancement follows the rule, **mode**, and **anchor field** (below).
- Do not store only “next due” with no series identity.

### Mode: regular vs on completion

Each series has a **recurrence mode**:

| Mode | Behavior |
|------|----------|
| **Regular** | A new instance is created on the schedule **whether or not** the previous one was resolved. Missed work accumulates (multiple open occurrences), up to a cap on open occurrences (see Building it). Timeline is driven by the anchor schedule (prior scheduled anchor + interval / calendar rules). |
| **On completion** | The next instance is created when the current one is **resolved** — not merely because the clock passed. **Resolved** means state **Done** or **Dropped** (ADR 0008). Both count as completion for spawning the next occurrence. The next anchor is the next instance of the rule strictly after the **resolution** moment. That moment starts the rule. **To-Do** does not spawn the next on its own. |

- Mode is user-visible and first-class on the series.
- **Regular** ≈ fixed schedule (rent, trash day). **On completion** ≈ “every 3 days after I last finished or dropped it.”
- There is **no separate Skip action**: use **Dropped** (works for recurring and one-off tasks).

### Anchor: which date field recurs

Recurrence is **based on exactly one** of the three task date fields (ADR 0006):

| Anchor | Meaning when the series advances |
|--------|-----------------------------------|
| **Defer** | Next **Defer** instant is computed from the rule |
| **Planned** | Next **Planned** instant is computed from the rule |
| **Due** | Next **Due** instant is computed from the rule |

- The anchor is part of the series definition (user-chosen).
- The other two date fields keep their offset from the anchor (amended 2026-10-02;
  see Building it). The rule drives only the anchor.
- **Regular:** the previous occurrence's anchor starts the rule, and the next
  anchor is the next instance strictly after it.
- **On completion:** the **Done/Dropped resolution time** starts the rule, and
  the next anchor is the next instance strictly after it.
- Both modes run the same expansion (see Expansion).

### Interval

Every series has:

- **`interval`**: positive integer (e.g. `3`, `36`)
- **`frequency`**: one of **`minutes`**, **`hours`**, **`days`**, **`weeks`**,
  **`months`**, **`years`**

Examples: every **3 days**, every **36 hours**, every **2 weeks**, every **1 month**.

### Weekly limits

When frequency is **weeks**:

- Optional **set of weekdays** the occurrence may land on (e.g. Mon/Wed/Fri).
  Weekdays are ISO (Monday is 1) and the week starts on Monday, the iCalendar
  default.
- With weekdays set, the next slot is the next listed weekday strictly after
  the start, in a week whose distance from the start's week is a multiple of
  `interval`. Every 2 weeks on Tue and Thu hits both days of the start's week,
  then those days two weeks later. With no weekdays, the slot is `interval`
  weeks ahead.

### Monthly limits

When frequency is **months**, the user may constrain which day of the month the
slot lands on:

1. **Calendar days of month**  
   Specific days: 1st, 22nd, … and **last** day of month.

2. **Nth weekday / special day**  
   Ordinal: **first** through **fifth**, or **last**.  
   Day kind:
   - Monday … Sunday  
   - **Work day** (implementation default: Mon–Fri unless user locale/settings say
     otherwise later)  
   - **Weekend day** (default: Sat–Sun)

Examples: “first Monday”, “last work day”, “third Friday”, “last day of month”.

Calendar days and an nth day may both be set. Months step by `interval` from
the start's month, and the slot is the soonest match strictly after the start.

- With neither, the slot keeps the start's day of the month. A month that lacks
  that day is skipped, and the interval is kept, so January's 31st is followed
  by March's.
- Calendar days alone are the days the slot may land on. A listed day the month
  does not have is skipped.
- An nth day alone is that day of the month. A fifth weekday the month does not
  have is skipped.
- With both, the slot is the nth day in a month where that day is also one of
  the calendar days. The 20th together with the first Monday occurs in a month
  where the 20th is that Monday. This is the RFC 5545 limit: `BYDAY` limits
  when `BYMONTHDAY` is present.

### End condition

A series may end by any of:

| End | Behavior |
|-----|----------|
| **None** | Continues until the series is archived/deleted or otherwise stopped. |
| **End date** | No new occurrences with anchor (or schedule instant) **after** this date/datetime. |
| **Count** | Stop after **N occurrences have been generated** (including the first). Not “N times marked Done.” Any generated instance counts, including ones later left To-Do, Done, or Dropped. |

- **End date** and **count** may both be set: stop when **whichever limit is hit first**.
- UI should make “never / until date / after N times / date and N” obvious.

### Resolution and mode (Done / Dropped)

Task states: ADR 0008. For recurrence:

| Mode | Done | Dropped | To-Do |
|------|------|---------|--------|
| **Regular** | Closes this instance as done | Closes this instance as dropped | Open; schedule still creates further instances independently |
| **On completion** | Resolves instance; **spawns next** | Resolves instance; **spawns next** (same scheduling as Done) | Does **not** spawn next |

- **Done** vs **Dropped** differ in history/meaning only for spawning: both are
  **completion for recurrence purposes** under on-completion mode.
- **Dropped** is the product name for what was informally called “skip”; it also
  applies to non-recurring tasks (cancel without doing).
- Next anchor (on completion) = the next instance of the rule strictly after the
  **time of transition to Done or Dropped**.
- Overdue open occurrences stay visible; do not silent-drop or mass-auto-complete.

### Representation

- **Primary:** structured columns / associated tables (mode, interval, frequency, anchor,
  weekday mask, monthly selectors, end_at, end_count, …) — **not** opaque RRULE-only storage.
- RRULE export/import is optional later if needed for calendar interop.

## Building it (2026-10-02)

Settled before the schema slice. Where this differs from the text above, this
section wins.

### A series repeats a task or a project

- `recurrence_series` is its own synced entity (ADR 0014): owner, the rule
  (mode, anchor, interval, frequency, weekdays, monthly selectors, end date,
  end count), `kind` (task | project), and `stopped_at`. Stopping a series
  keeps it, so its occurrences keep their history.
- A change to any part of the rule patches the whole rule, so two offline
  edits leave one of the two rules, never a mix that does not fit together
  (as Defer does, ADR 0006).
- Tasks and projects both carry `series_id` and `occurrence_for`. A series has
  occurrences of its own kind only. The first build repeats tasks; projects
  follow without a schema change.
- The series holds no title, notes, location, or tags. Those come from the
  occurrences.

### The occurrence

- `occurrence_for` is the anchor the rule produced: "the occurrence for
  Friday 17:00". It is set on insert and no client may patch it. Moving this
  occurrence's Due to Saturday leaves `occurrence_for` on Friday. It is not
  "scheduled": that word reads as Planned. `(series_id, occurrence_for)` is
  unique.
- A rule-created id is UUIDv5 of the series and `occurrence_for` (ADR 0014). The
  task a rule is added to stays the first occurrence, with its own v7 id and
  `occurrence_for` set to its anchor field, which must have a value.
- A generated id that already exists is never created again, discarded or
  not. Deleting an occurrence does not bring it back.

### The next occurrence copies the latest

- The latest occurrence is the one with the greatest `occurrence_for`. The next
  copies its title, notes, URL (ADR 0022), location, parent task, and tags, sits right after
  it among its siblings, and starts To-Do.
- The anchor field gets the new `occurrence_for`. Each other date that is set
  keeps its distance from the latest's anchor field on the user's zone clock
  (same days, same local time), so "defer 2 days before due" holds across a
  DST change. The offset is part of the pure function and its fixtures.
- A task's subtasks are not copied in the first build.
- A project occurrence will copy the latest project with its task tree, every
  task To-Do. Copied task ids are UUIDv5 of the new project id and the source
  task id, so both sides mint the same tree.
- A rule change applies from the next generated slot. Existing occurrences
  keep their `occurrence_for`.
- Reopening an occurrence does not undo the one its completion created. Both
  stay, and both count toward the end count.

### Regular mode and the open cap

- A series always has one occurrence scheduled after now. When its slot
  passes, the generator creates the following one. Earlier occurrences stay
  open until resolved.
- A series has at most **10** open (To-Do) occurrences. At the cap the
  generator creates nothing. The number is fixed, not a user setting.
- When the series drops below the cap again, generation resumes at the first
  slot after now. Missed slots are skipped: they never become rows and do not
  count toward the end count.
- The server creates every occurrence after the first (ADR 0014, amended
  2026-10-03). A client joins a task to a series only as its first
  occurrence.

### History

There is no completions table. A series' occurrences are its history:
`occurrence_for`, `resolved_at`, and Done or Dropped. Synced rows are never
hard-deleted (ADR 0014), so streaks, completion rates, and lateness can be
worked out from them later. Skipped slots show as gaps between
`occurrence_for` values.

## Expansion (2026-10-07)

The calendar expansion follows RFC 5545 recurrence rules, so a rule a calendar
user already knows lands on the same days. The series stays structured columns.
An RRULE string is not the store. Where an earlier paragraph disagrees, this
section wins.

- One expansion for both modes. Mode chooses the instant the rule starts from:
  the previous occurrence's anchor, or the resolution time. The result is the
  next instance strictly after that instant.
- Minutes and hours add elapsed UTC time.
- Days, weeks, months, and years step on the user's zone calendar and keep the
  local time. The week starts on Monday.
- A local time the zone skips, or that occurs twice, resolves through
  `Marskal.Dates.from_local/4`, the same instant a date entered on that wall
  clock gets.
- A date the month or year does not have is skipped. It is not generated, and
  it does not count toward the end count.
- `ends_at` is inclusive: a slot at that instant is kept.
- End count is N generated, including the first, which is what RFC 5545 `COUNT`
  does. The generator enforces it, along with the open cap.

## Consequences

- Phase 3 is a major product surface, not a bolt-on “repeat every week” checkbox.
- Schema must link series → **mode** + anchor enum + rule params + end date/count;
  occurrences carry state (ADR 0008) and Defer/Planned/Due as appropriate.
- UI must expose: mode (regular | on completion), anchor, interval+frequency,
  weekly days, monthly day patterns, end date, end count; task actions Done / Dropped
  (not Skip; no task On Hold — use Defer).
- Tests should cover: each frequency; both modes; weekly/monthly limits; end date;
  **end count = N generated**; both ends together; on-completion spawns on **Done and
  Dropped**; anchor ∈ {Defer, Planned, Due}; regular mode creating the next instance
  even when the previous is still open; other dates keeping their offset across a
  DST change; the open cap and the slots skipped after it; a discarded occurrence
  not coming back.
- Structured rules first; mode resolves schedule-vs-resolution advancement; count and
  Done/Dropped-as-resolution are fixed as above. States detailed in ADR 0008.
