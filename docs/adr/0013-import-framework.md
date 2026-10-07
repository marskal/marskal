# 0013. Import framework

## Status

Accepted; amended 2026-10-04 (re-import updates); amended 2026-10-07 (import problems)

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
  replay master + transactions). Flatten nested actions until `tasks.parent_id`
  exists.
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
  inside the folder. Sections, subtask parent, a Todoist due date (planned),
  a deadline (due), and the recurrence text stay in `extras`. Completed-task
  history is not in the sync snapshot and is not imported.

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
  recurrence, Missing section, Shortened title, Shortened notes. The tag view
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
- A source convention with no Marskal column (OmniFocus flagged, Todoist
  priority) is not a problem; it stays in `extras` for now.

## Consequences

- New sources add an adapter + sniff, not new controllers.
- `extras` keeps unmapped values for inspection, not for backfill. The payload
  is gone after apply, so a value is only as complete as what the adapter
  stored. OmniFocus tag definitions, for one, were never stored. Before
  launch, a field that gains a home is picked up by importing again, not by a
  backfill job.
- Jobs run through Oban.
