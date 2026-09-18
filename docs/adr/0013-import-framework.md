# 0013. Import framework

## Status

Accepted

## Context

Users will migrate from OmniFocus, Todoist, and similar apps. The first product
surface is **upload a backup file**. Later we want **“Sign in to Todoist”** (OAuth)
without a second pipeline. Competing formats differ; Marskal’s model does not
(ADR 0008–0010). Tags, dates, outliner, and recurrence are not in the schema yet
(ADR 0005–0007, 0009).

## Decision

- **Adapters** parse a source into a canonical `Imports::Graph` (folders,
  projects, tasks). No gems from competing apps.
- **Fetchers** only acquire bytes: **file** (Active Storage) now; **OAuth** later
  as another fetcher that yields a tempfile. OmniFocus has no public API — file
  only. Todoist OAuth is a later adapter + fetcher, not a new framework.
- **`import_batches`** (per user, source, channel, status, stats) own the upload.
  **`import_items`** map `(user, source, source_id)` → Marskal rows (explicit FKs,
  not polymorphic). Re-import **skips** existing source ids (does not overwrite).
- Unmapped Phase 2/3 fields (tags, defer/planned/due, parent, repeat, flagged)
  go in **`import_items.extras` jsonb**, not notes.
- First adapter: **OmniFocus `.ofocus` / `.ofocus-backup`** (zip-of-zips XML,
  replay master + transactions). Flatten nested actions until `tasks.parent_id`
  exists.

## Consequences

- New sources add an adapter + sniff, not new controllers.
- Applying dates/tags later is a job over `extras`, not a re-parse requirement.
- Jobs run through Active Job (async in development; Solid Queue in production).
