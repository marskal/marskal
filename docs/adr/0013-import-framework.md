# 0013. Import framework

## Status

Accepted

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
  not polymorphic). Re-import **skips** existing source ids (does not overwrite).
- Unmapped Phase 2/3 fields (defer/planned/due, parent, repeat, flagged) go in
  **`import_items.extras` jsonb**, not notes.
- When a field gains a Marskal home, the adapter maps it and it leaves
  `extras`. Tags do so with the tags slice: the OmniFocus adapter parses tags
  and contexts into the graph as their own items (ADR 0005).
- First adapter: **OmniFocus `.ofocus` / `.ofocus-backup`** (zip-of-zips XML,
  replay master + transactions). Flatten nested actions until `tasks.parent_id`
  exists.

## Consequences

- New sources add an adapter + sniff, not new controllers.
- `extras` keeps unmapped values for inspection, not for backfill. The payload
  is gone after apply, so a value is only as complete as what the adapter
  stored. OmniFocus tag definitions, for one, were never stored. Before
  launch, a field that gains a home is picked up by importing again, not by a
  backfill job.
- Jobs run through Active Job (async in development; Solid Queue in production).
