# 0026. Project review

## Status

Proposed

## Context

Soft-GTD has five steps (ADR 0005), and the fourth, **Reflect**, has no
support yet: nothing tells the user which projects they have not looked at
in a while. A project can sit stalled, with no next action, or be deferred
indefinitely and forgotten (ADR 0008).

There are two common shapes for a review:

- **A guided session**, as in the GTD book: empty the inbox, look at the
  calendar, walk every project, check Waiting and Someday. It is one
  sitting, and nothing about a single project is recorded.
- **Per-project review**, as in OmniFocus: each project has a review
  interval and a next review date. A Review view lists the projects that
  are due, and the user marks each one reviewed. The weekly review is the
  default interval rather than a separate ritual, and a someday project can
  be reviewed monthly while an active one comes up every week.

The per-project shape keeps its state on the rows it is about, so it syncs
the same way as everything else (ADR 0014), and a review can be split over
several sittings or devices without a session to resume.

## Decision

### What is reviewed

- **Projects** are reviewed. Tasks, tags, and folders are not. Waiting and
  Someday stay tag conventions (ADR 0005), and the user opens those tags
  when they want to check them. No state records that.
- There is no review session, checklist, or "finish review" step.

### Fields on projects

- **`review_interval`** (`interval`, required). It is written as an
  ISO 8601 duration, `P[n]Y[n]M[n]W[n]D`: `P1W`, `P2W`, `P1M`, `P1M15D`.
  It has date parts only. A `CHECK` refuses a time part
  (`date_trunc('day', review_interval) = review_interval`), a negative
  part, and a zero interval, because a review is due on a day.
- **`next_review_on`** (`date`, required): the day in the user's timezone
  when the project is due for review. It is a calendar day, not an instant,
  because a review is due on a day rather than at a time.
- **`last_reviewed_at`** (`timestamptz`, nullable): when it was last marked
  reviewed. It is shown, not computed from.
- The user may set `next_review_on` directly, for example to bring a
  project forward or push it back, without marking it reviewed.

### Defaults

- A new preference (ADR 0023): **`review_interval`**, an `interval` with
  the same `CHECK`, default `P1W`. As with `week_start`, a new project
  copies it when it is made, and later changes to the preference do not
  move existing projects.
- A new project's `next_review_on` is its creation day plus its interval,
  on the user's clock.
- At migration, existing projects get 1 week and `next_review_on` is the
  migration day, so the first review covers all of them.

### Marking reviewed

- **Mark reviewed** sets `last_reviewed_at` to now and `next_review_on` to
  today plus the interval, in the user's timezone. Years and months are
  added first, then days, as Postgres does for `date + interval`. A step
  that lands past a short month's end is clamped to its last day, as in
  ADR 0007.
- Changing the interval moves `next_review_on` to `last_reviewed_at` (or the
  creation day, if never reviewed) plus the new interval. If that day has
  passed, the project is due now.
- Each is an ordinary write through `Marskal.Changes.apply/4`, appended to
  the change feed. All three fields are client-writable (ADR 0019). On the
  wire the interval is its ISO 8601 string. The web app reads it as an
  Elixir `Duration` (Ecto `:duration`, with Postgrex decoding `interval`
  to `Duration`), and the Rust library as a jiff `Span`. An offline client
  computes the next day itself from the interval and the user's timezone.
  A concurrent edit to the same field follows the usual rule: the later
  command wins (ADR 0014).
- Postgres keeps an interval as months, days, and microseconds, so weeks
  come back as days: `P2W` is stored and pulled as `P14D`. The UI shows a
  whole number of weeks as weeks ("Review every 2 weeks"), and a mixed
  interval in its parts ("every 1 month, 15 days").

### Which projects are due

The **Review** view lists projects that:

- are **To-Do**, and not discarded,
- have `next_review_on` on or before today in the user's timezone.

Deferred projects, indefinite ones included, **are** listed: the review is
where the user decides to resume one. Projects in a Dropped folder are
listed too, because dropping a folder does not resolve its projects
(ADR 0009). Done and Dropped projects are never listed.

The list is ordered by `next_review_on`, then in sidebar order. Each row
shows its folder, its deferral, and whether it is **stalled**: To-Do, not
deferred, and with no available task (ADR 0008). Opening a row shows the
project's outline and a **Mark reviewed** action, which moves on to the
next due project.

The sidebar shows the number of projects due. The Review view also shows
how many items are in the inbox, as a reminder to clear it, without
blocking anything.

### Repeating projects

The next occurrence copies `review_interval` from the occurrence before it (ADR 0007). Its `last_reviewed_at` is empty, and
its `next_review_on` is its creation day plus its interval.

### Import

- **OmniFocus:** a project's review interval, last review, and next review
  map to the three fields when the backup includes them. Its intervals are
  in days, weeks, months, and years, so they map directly. An interval the
  import cannot read leaves the project with the default interval and an
  import problem saying what it was (`Imports.Problems`).
- **Todoist** has no reviews, so imported projects get the defaults.
- On re-import, the user's own review state wins under the three-way merge
  (ADR 0013), as with any other field.

## Consequences

- Review does not change availability. A project that is due for review
  stays in the open stream and in its views as usual.
- Repeat rules keep their number and unit (ADR 0007). There the unit
  decides which `on_days` rows apply, which a duration cannot express.
- The Rust library's local schema gains the three project columns and the
  preference, with the interval stored as text. A client asks for a snapshot after upgrading, as with
  ADR 0025.
- The terminal client can add `marskal review` (list the projects due) and
  `marskal review --done <id>` later. This ADR does not require them.
- A guided session (inbox, agenda, tags, then projects) can be built later
  as a view over this state, without new fields.
- No notifications. Due-for-review is only visible in the app.
