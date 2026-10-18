# 0013. Import framework

## Status

Accepted; amended 2026-10-04 (re-import updates); amended 2026-10-07 (import problems); amended 2026-10-09 (Todoist repeats); amended 2026-10-16 (OmniFocus repeats)

The framework stands and is ported to Elixir ([ADR 0016](0016-elixir-phoenix-web.md)):
`Imports.Graph`, `Imports.OmnifocusAdapter`, and Oban jobs in place of Active
Job. The file fetcher stores the upload in `import_batches.payload` instead of
Active Storage, and clears it once the batch is applied, fails, or sits
unapplied for 24 hours.

## Context

Users will migrate from OmniFocus, Todoist, and similar apps. The first product
surface is **upload a backup file**. Later we want **“Sign in to Todoist”** (OAuth)
without a second pipeline. Competing formats differ; Marskal’s model does not
(ADR 0008–0010). Dates, outliner, and recurrence are not in the schema yet
(ADR 0006, 0007, 0009). Tags arrive in Phase 2 (ADR 0005).

## Decision

- **Adapters** parse a source into a canonical `Imports::Graph` (folders,
  projects, tasks). No gems from competing apps.
- **Fetchers** only acquire bytes: **file** (Active Storage) now; **OAuth** later
  as another fetcher that yields a tempfile. OmniFocus has no public API — file
  only. Todoist OAuth is a later adapter + fetcher, not a new framework.
- **`import_batches`** (per user, source, channel, status, stats) own the upload.
  **`import_items`** map `(user, source, source_id)` → Marskal rows (explicit FKs,
  not polymorphic). Re-import **updates** existing source ids by a three-way
  merge (see below).
- Unmapped fields go in **`import_items.extras` jsonb**: structured data for
  us, for mapping them later. What the user needs to fix an item by hand
  goes in its notes, with a tag (see Import problems).
- When a field gains a Marskal home, the adapter maps it and it leaves
  `extras`. Tags do so with the tags slice: the OmniFocus adapter parses tags
  and contexts into the graph as their own items (ADR 0005).
- First adapter: **OmniFocus `.ofocus` / `.ofocus-backup`** (zip-of-zips XML,
  replay master + transactions). A nested action is a subtask of its parent
  action (`tasks.parent_id`), siblings in the backup's rank order. The
  folders and projects of one folder are one sibling list (ADR 0009), also
  in rank order.
- **Todoist** is the OAuth fetcher. The user signs in with scope `data:read`.
  Marskal exchanges the code, downloads one API v1 sync snapshot (`user`,
  `projects`, `items`, `sections`, `labels`, `folders`), stores that JSON as
  the batch payload, and discards the token. Refresh tokens are not kept.
  Client id and secret come from `TODOIST_CLIENT_ID` and
  `TODOIST_CLIENT_SECRET`; the redirect defaults to
  `/imports/todoist/callback` on the public host (`TODOIST_REDIRECT_URI`
  overrides it).
- What already has a home is applied: folders, projects, tasks, and labels
  as tags. The inbox project is not created. A nested Todoist project
  becomes a folder. A parent with no tasks of its own is only that folder;
  a parent that also has tasks keeps them in a project named "<name> tasks"
  inside the folder, first there. A subtask stays under its parent task.
  Folders, projects, and subtasks keep their `child_order`; Todoist orders
  workspace folders apart from the projects beside them, so where those
  meet the order is a guess. A due date is Planned and a deadline Due.
  Priority is a flag or a tag (ADR 0025). Section, order key, the due date's zone, and
  the repeat text stay in `extras`. Completed-task history is not in the
  sync snapshot and is not imported.

### Re-import updates (amended 2026-10-04)

Importing the same source again updates what was imported before, so a
source keeps being useful while the user moves over, and adapters can be
tried again as they learn more fields.

- **Base:** `import_items.fields` holds, per merged field, what the source
  said at the last import, plus the tag ids it set. Items imported before
  the column existed take the import's insert from the change feed (it is
  the item's first change), over the defaults it left out. Their tag base is
  the source's tags the item has now.
- **Merge, per field:** a field the source changed since the base is
  written, unless the user changed it too. Then the user's value stays, and
  the batch reports it as kept. Fields that move together merge as one: a
  task's location (`inbox` + `project_id`, ADR 0017) and Defer (ADR 0006).
  Tags merge as a set: the source's additions and removals since the base,
  leaving the tags the user added or removed alone. The base then becomes
  what the source says now.
- Each update is an ordinary command through `Marskal.Changes`, so it syncs.
  An unchanged source writes nothing.
- An item the user **deleted** while the source still has it is imported
  **again, as a new record**, and its item row points at that. Deleting is
  for mistakes (ADR 0014), and tombstones are invisible, so keeping it
  deleted would look like an item that fails to import. The tombstone stays
  as it was, so clients see one delete and one insert. The batch counts
  these, and the result page says so. To keep something out, Drop it.
- An item missing from the source is left alone: a Todoist snapshot leaves
  out completed tasks, so missing does not mean deleted.
- A tag the import **reused** (the user's own, same name and place) is never
  updated. A change that would not validate, such as a folder move into its
  own subtree or a tag rename onto a taken name, is kept as the user has it.
- The whole apply stays one transaction.

### Import problems (amended 2026-10-07)

What an import cannot carry over is easy to find and fix
(`Marskal.Imports.Problems`).

- The item gets a tag under **Import problems**, one per kind: Missing
  recurrence, Approximate repeat rule, Missing section, Shortened title,
  Shortened notes. The tag view
  then lists everything to fix, and the user removes the tag when done.
- Its notes end with a block saying what is missing, e.g. the repeat rule as
  the source stores it, or the rest of a title past the title limit:

      ---
      Imported from OmniFocus:
      - Repeat: FREQ=WEEKLY;BYDAY=TU (schedule from-completion)

- The block is never cut. Notes that do not fit beside it within the notes
  limit are, and the item is tagged Shortened notes; that text is lost.
- Tags and block come out the same on every import, so the three-way merge
  keeps them away once the user removed them, and drops them from untouched
  items once the adapter can map the field.
- A folder has no tags or notes. What one cannot keep is listed on the import
  page instead.
- A source convention with no Marskal column is not a problem; it stays in
  `extras` for now. OmniFocus flagged and Todoist priority have one now
  (ADR 0025).

### Todoist repeats (amended 2026-10-09)

Todoist gives a repeat only as the words the user typed (`due.string`).
`Marskal.Imports.TodoistRecurrence` reads the common forms into a rule
(ADR 0007) on the planned date: every so many units, weekdays, days of the
month and nth weekdays, days of the year, and `every!` as after completion.

- The task becomes the first occurrence of a new series, on import or on
  re-import, so tasks imported before this get their series too. A task
  already in a series, or one the user stopped, keeps what it has.
- Once a task is in a series, a re-import leaves its dates alone. Todoist
  moves a repeating task's date when it is done there; in Marskal the series
  makes the next occurrence instead.
- A repeat with no date, or one in a form not read, stays a Missing
  recurrence problem with its text in the notes block, as before.
- Free-form text, such as "every other tuesday starting next month" or
  "every 3rd workday until june", is not read yet. It could be later,
  through Todoist's own date parser or a language model.
- OmniFocus repeats stay problems. Its RRULE text maps more directly and
  can follow the same way (it does, below).

### OmniFocus repeats (amended 2026-10-16)

OmniFocus stores a repeat as an RFC 5545 RRULE, with how it is scheduled
beside it. `Marskal.Imports.OmnifocusRecurrence` reads it into a rule
(ADR 0007), on the date OmniFocus names, for tasks and projects alike.

- FREQ and INTERVAL, weekdays (BYDAY) for a weekly rule, days of the month
  and nth weekdays for a monthly one (BYMONTHDAY, BYDAY with an ordinal, and
  BYSETPOS over the work or weekend days), the same with BYMONTH for a
  yearly one, COUNT, UNTIL, and WKST.
- Mode and anchor come from `repetition-schedule-type` and
  `repetition-anchor-date`, or, in older backups, `repetition-method`: fixed
  is regular on the Due date (Defer, then Planned, without one),
  start-after-completion is on completion on Defer, due-after-completion on
  Due. The oldest backups' short form, `@1w`, is read too.
- Where Marskal has no exact match, the closest rule is imported and the
  item gets an **Approximate repeat rule** problem saying what differs: a
  repeat from completion with days keeps its interval but not the days
  (ADR 0007 has no day limits after completion), and a regular one with
  catch-up off skips passed dates, as every regular series does.
- Anything else (BYHOUR, BYWEEKNO, BYDAY without an ordinal in a month), or a
  repeat without the date it moves, stays a Missing recurrence problem.
- Re-import works as for Todoist: a task or project becomes a first
  occurrence once, and its series then owns its dates.

## Consequences

- New sources add an adapter + sniff, not new controllers.
- `extras` keeps unmapped values for inspection, not for backfill. The payload
  is gone after apply, so a value is only as complete as what the adapter
  stored. OmniFocus tag definitions, for one, were never stored. Before
  launch, a field that gains a home is picked up by importing again, not by a
  backfill job.
- Jobs run through Oban.
