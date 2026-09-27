# 0005. Soft-GTD and nested tags

## Status

Accepted. Amended before the tags slice to settle subtree filters, tag
states, uniqueness, and link rows.

## Context

Classic GTD uses **contexts** (`@home`, `@errands`, …) and fixed lists (next, waiting,
someday, …). We want GTD-inspired **flow** without rigid list enums. Organization
should be flexible (people, duration, place, energy, etc.), support **Unicode and
emoji**, and allow hierarchy such as `Person` → `Wife`, `Location` → `Home`.

Alternatives considered for hierarchy storage:

- First-class Context model — rejected (too rigid; soft-GTD).
- Postgres **`ltree`** — rejected (label charset blocks normal i18n/emoji).
- Slash-separated `text` path only — workable but separator-in-name issues.
- **`ltree`-like GENERATED path** — generated columns cannot walk `parent_id`; full
  path still needs denormalized parent data; UI will render fancy HTML anyway.
- **`parent_id` + `parent_path text[]`** — accepted.

## Decision

### Product

- **Soft-GTD:** capture → clarify → organize → reflect → engage — without enforcing
  full GTD dogma or a multi-list placement enum (ADR 0010).
- **Inbox** is a boolean on tasks (unclarified). **Open tasks** (not inbox, to-do) is
  the default engage stream. **Projects**, **tags**, and **dates** build other views.
- **No** first-class Context entity or hardcoded context / list vocabulary in schema.
- **Waiting**, **Someday**, and similar are **user tag conventions** (not `list` enums).
- **Nested tags** only; many tags per entity; per-user tag trees.
- Example segments (user convention, not schema enums): `Person`/`Wife`,
  `Duration`/`Short`, `Location`/`Home`, and optionally root tags like `Waiting` /
  `Someday`.
- Tags apply to **tasks** and **projects**.
- **Tags ship in Phase 2** (with projects & planning), not Phase 1.
- Phase 4 may polish tag UX (create-on-type, nest browsing, filters).

### Project tags and inheritance

- A **project** may have zero or more tags (same tag model as tasks).
- **Inheritance:** tags on a project **automatically apply to all tasks in that project**.
- A task’s **effective tags** = **union** of:
  - tags assigned directly on the task, and
  - tags assigned on its project (if any).
- **No inheritance from a parent task.** A subtask's effective tags are its own
  plus its project's. This holds once the outliner lands (ADR 0009).
- Prefer **inheritance at read/filter time** (or equivalent), not copying project tags
  onto every task row on write — so changing project tags updates effective tags for
  all member tasks without mass rewrites. (Denormalized cache is an optional later
  optimization, not required.)
- UI may show inherited tags as such (e.g. distinct from task-only tags) when helpful.
- Direct task tags remain useful for task-specific labels not shared by the whole project.
- Moving a task between projects changes inherited tags with the new project’s set.

### Tag view and filters

- Selecting a tag shows an **outline**. First come the tasks that carry that tag
  itself. Then comes one group per child tag, holding that child's tasks and,
  nested the same way, its own children.
- A tag therefore matches its whole subtree. Selecting `Person` includes
  `Person/Wife`.
- Matching uses **effective** tags. A task in a project tagged `Person/Wife`
  appears under `Person/Wife`.
- A task appears under every tag it carries. A task tagged both `Person` and
  `Person/Wife` shows in both places.
- v1 filters: one tag (with its subtree), and **untagged** (no effective tags).
  Several tags combine with **AND**.
- Tag views list **to-do** tasks, inbox tasks included (ADR 0010). A visibility
  selector for finding Done and Dropped items again comes later, for all
  views.
- Tags get a `rank` from the start: new tags go last, imports keep the
  source order. Drag-and-drop reordering is a separate effort across tasks,
  projects, folders, and tags.
- Subtree matching expands the selected tag to its descendant ids in app code
  (a user's tree is small) and queries `tag_id = ANY(ids)`. `parent_path`
  serves display, not matching.

### Tag states

**Active | On Hold | Dropped**. This is separate from task and project state
(ADR 0008). Tasks and projects still have no On Hold.

- **Active** (default): no effect on tasks.
- **On Hold:** a task with any on-hold effective tag is **unavailable**, even if
  its other tags are active.
- **Dropped:** the tag is hidden from the tag list and pickers. It stays on its
  tasks. A task whose effective tags are **all** dropped is **unavailable**.
- **On Hold is per tag.** Putting `Person` on hold does not block a task
  tagged only `Person/Wife`; the child stays active and its task stays
  available.
- **Dropped covers the subtree.** Dropping `Person` hides `Person/Wife` too,
  and a tag under a dropped ancestor counts as dropped when deciding whether a
  task is available.
- **Unavailable** tasks leave the open stream like deferred ones (ADR 0006).
  They show when unavailable and deferred items are shown, and they stay in
  project and tag views, marked as such.

### Names and uniqueness

- `name` is one segment. Any character is allowed, including `/` and `:`
  (`Someday/maybe`), and Unicode and emoji. Trim whitespace and normalize to
  NFC before saving. The path is a list of segments, never a joined string,
  so nothing is escaped or split on save.
- Names are **unique per parent**, ignoring case: one live tag per
  `(user_id, parent_id, name)`, with `name citext` and root tags counted as
  one parent (`NULLS NOT DISTINCT`). Discarded tags do not count.
- Online, a create or rename that clashes is rejected. Offline duplicates are
  merged on sync (ADR 0014).
- Siblings have a manual order, a fractional `rank` as ADR 0014 specifies.

### Display and search

- The UI shows a path as separate segments with a chevron between them:
  `Lists › Someday/maybe`. The chevron is its own element (`aria-hidden`),
  never part of a name. Plain-text contexts (titles, search results) use
  ` › `.
- **Autocomplete accepts every common separator** in what the user types: `/`,
  `:`, `›`, `>`, and `\`. A query is matched two ways, and both kinds of hit
  are offered:
  - **Literally**, against a tag's own name: `som/may` finds `Someday/maybe`.
  - **As a path:** split on separators, each piece is a case-insensitive
    prefix of a segment, in order, with the last piece matching the tag
    itself. `som/may` finds `Someday › Maybach`. Earlier pieces may skip
    ancestors, so `per/wi` finds `Person › Family › Wife`.
- Ranking: exact name before prefix, fewer skipped segments first, then
  shallower tags.
- Creating from the picker makes a tag with the typed text as its literal
  name, under the parent chosen in the picker. Typing a path to create
  several levels at once is Phase 4 polish, not v1.

### Storage

```text
tags
  id                -- uuid, DEFAULT uuidv7()
  user_id
  name              -- citext; one segment; Unicode/emoji OK
  parent_id         -- null = root
  parent_path       -- text[]; ancestor names root→parent; {} at root
  state             -- active | on_hold | dropped
  rank              -- fractional sibling order
  merged_into_id    -- set when an offline duplicate was folded into another tag
  discarded_at

task_tags / project_tags
  id                -- UUIDv5 of the pair, see below
  user_id
  task_id | project_id
  tag_id
  discarded_at
```

- Full path in app code: `parent_path + [name]` (no separate stored path column
  unless a later need appears; **no** `GENERATED ALWAYS` path).
- Create under parent: `parent_path = parent.parent_path + [parent.name]`.
- Rename/reparent (rare): cascade-update descendants’ `parent_path` in app code.
- Presentation: render hierarchy in **HTML** from segments (view concern).
- **Link rows are entities**, not a bare HABTM table: their own id, owner, and
  tombstone (ADR 0014). The id is **UUIDv5** of the pair, so tagging the same
  task twice, from any device, is the same row. Untagging sets `discarded_at`;
  tagging again clears it. That is an explicit re-tag, not a stale patch
  reviving a discard.
  - Namespace: `a5c0ffee-0005-5000-8000-000000000005`
  - Name (UTF-8): `task|{task_id}|{tag_id}` or `project|{project_id}|{tag_id}`,
    ids as canonical lowercase UUIDs.
- References stay inside one owner: composite foreign keys `(tag_id, user_id)`,
  `(task_id, user_id)`, `(project_id, user_id)`, as for folders and projects.
- **Deleting** a tag discards it, its descendants, and their link rows. Dropping
  is the everyday way to retire a tag. Deleting is for mistakes.
- Do not require duplicated project tag rows on every task for inheritance. Do not
  use `ltree`.

### Import

- The OmniFocus adapter parses tags (name, parent, status, order) into the
  graph and links them to tasks and projects. OmniFocus contexts map to tags.
- Not live yet, so there is no backfill of earlier imports.

### Sharing (later)

Tags are personal trees (ADR 0003). A link row belongs to the tagged task's
owner, so a member of a shared folder cannot put their own tag on a task they
do not own. How tags, and tag state, behave on shared folders needs its own
decision when sharing ships.

## Consequences

- Phase 1 stays focused on inbox boolean + open stream + states, without tagging UI.
- Phase 2 adds tags on tasks **and** projects, plus inheritance in filters/display;
  Waiting/Someday-style perspectives are tag filters, not list columns.
- The tags slice brings `discarded_at` forward for `tags`, `task_tags`, and
  `project_tags`, ahead of the rest of ADR 0014's pre-sync work.
- "Available" becomes a computed property of a task: not deferred, and not
  blocked by tag state. The open stream and later the agenda filter on it.
- Hierarchy queries expand ids in app code; no `ltree` extension. A user's
  tree is small enough to load per request. If subtree filters ever have to
  run inside SQL (combined filters with pagination over large task sets, or
  subtree checks across shared trees), add `ancestor_ids uuid[]` with a GIN
  index and query `ancestor_ids @> ARRAY[id]`, or use a recursive CTE over
  `parent_id`. Either is a migration and a backfill: the path is derived and
  not synced (ADR 0014), so clients and the sync protocol do not change.
  `ltree` over ids would also work, but adds an extension for no gain over
  the array.
- Unicode-first tags remain viable long-term.
- Tag filter queries must join project tags for tasks that belong to a project.
- Tests: effective tags (task ∪ project, never parent task); subtree outline
  grouping; untagged filter; state propagation to children and its effect on
  availability; case-insensitive uniqueness per parent; link-id vectors; untag
  and re-tag on one row; delete cascades discards.
