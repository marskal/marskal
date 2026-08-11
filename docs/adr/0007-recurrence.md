# 0007. Recurrence (core differentiator)

## Status

Accepted

## Context

Recurrence is where Marskal Tasks should **shine**. Soft-GTD capture/clarify and
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
| **Regular** | A new instance is created on the schedule **whether or not** the previous one was resolved. Missed work can accumulate (multiple open occurrences) unless the product later adds catch-up policies. Timeline is driven by the anchor schedule (prior scheduled anchor + interval / calendar rules). |
| **On completion** | The next instance is created when the current one is **resolved** — not merely because the clock passed. **Resolved** means state **Done** or **Dropped** (ADR 0008). Both count as completion for spawning the next occurrence. The next anchor is computed from the **resolution** moment (then apply interval + weekday/month limits). **To-Do** does not spawn the next on its own. |

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
- Non-anchor date fields on an occurrence are **not** auto-advanced unless product
  behavior is explicitly defined later (default: only the anchor field is driven by
  the series).
- **Regular:** next anchor from the schedule (previous scheduled anchor + rule).  
  **On completion:** next anchor from **Done/Dropped resolution time** + rule.

### Interval

Every series has:

- **`interval`**: positive integer (e.g. `3`, `36`)
- **`frequency`**: one of **`minutes`**, **`hours`**, **`days`**, **`weeks`**,
  **`months`**, **`years`**

Examples: every **3 days**, every **36 hours**, every **2 weeks**, every **1 month**.

### Weekly limits

When frequency is **weeks** (and for week-based patterns generally):

- Optional **set of weekdays** the occurrence may land on (e.g. Mon/Wed/Fri).
- If set, advancement picks the next valid weekday consistent with the interval and
  anchor timeline (define edge cases in tests: “every 2 weeks on Tue+Thu”, etc.).

### Monthly limits

When frequency is **months**, the user may constrain the day-of-month pattern using
one of these styles (or a clear single chosen style per series):

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

Exactly how multiple monthly constraints combine (if more than one day is selected)
should follow a simple rule: e.g. **set of matching days in the month**, next
occurrence = soonest match after “now”/after previous, stepping by `interval` months
from the series month grid. Specify in code with tests; keep UX obvious.

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
- Next anchor (on completion) = **time of transition to Done or Dropped** + rule.
- Overdue open occurrences stay visible; do not silent-drop or mass-auto-complete.

### Representation

- **Primary:** structured columns / associated tables (mode, interval, frequency, anchor,
  weekday mask, monthly selectors, end_at, end_count, …) — **not** opaque RRULE-only storage.
- RRULE export/import is optional later if needed for calendar interop.

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
  even when the previous is still open.
- Structured rules first; mode resolves schedule-vs-resolution advancement; count and
  Done/Dropped-as-resolution are fixed as above. States detailed in ADR 0008.
