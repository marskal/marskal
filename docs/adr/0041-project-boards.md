# 0041. Project boards

## Status

Proposed

## Context

Many people plan a project as a board: a column for each stage of the
work, and cards that move from left to right until they are done. Others
keep a list but group it under headings. Marskal can do neither. A project
page is an outline of its tasks, with no way to group them into stages.
Todoist calls those groups sections, and an import that meets one today
has nowhere to put it: the task gets a **Missing section** import problem
(ADR 0013).

The stages belong to the project. A software project might go Ready, In
progress, Review; a house move might go Pack, Move, Unpack. So they cannot
be task states. Tasks keep To-Do, Done, and Dropped (ADR 0008), and
Marskal has already turned down a fixed set of lists (ADR 0010). The
stages have to be data the user names, one set per project.

A board for a tag would be useful too, but a task has one project and many
tags, so its card could belong in several columns at once. That needs a
different model, and it comes later.

## Decision

A project can be drawn as a board. The columns are the **backlog**, the
**sections** the user names, and **Done**. A card starts in the backlog,
moves left to right through the sections, and leaves the board when it is
completed. When the project is drawn as a list, the same sections are
headings. A project without sections looks the way it does today.

Tag boards are still a goal, but they are not part of this work (see
[Tag boards, later](#tag-boards-later)).

### Concepts

| Term | Meaning |
|---|---|
| **Section** | A named stage in one project, with an order among that project's sections. A root task of the project can be filed in one. |
| **Backlog** | The project's To-Do root tasks that have no section. It is where new tasks land. It is always the first column on a board. It is not stored. |
| **Done column** | The board's view of tasks whose state is Done. It is not a section. |
| **Layout** | `list` or `board`, stored on the project. |

A board is a pipeline: the user's sections are stages, and work moves
through them until it is done. That does not bring back a workflow status
(ADR 0008, ADR 0010):

- Task state stays To-Do, Done, and Dropped. A section is not a state.
- Each project has its own sections, which the user names. Nothing in
  the schema lists stages.
- Only the project page reads sections. Open tasks, the agenda, Flagged,
  Review, tag pages, Go to, and the terminal ignore them.

### Behavior

#### Layout

Every project page heading has a List / Board switch (`aria-pressed`). It
patches `projects.layout`, which defaults to `list` and syncs with the
project. The board has no separate on-switch. A list without sections is
today's page. A board without sections has two columns, Backlog and Done.

#### The board

Columns, left to right: **Backlog**, the live sections by `rank`, **Done**,
and then **Dropped** only when the Dropped toggle is on and the column has
cards.

- Cards are the project's root tasks. Subtasks render inside the card,
  in outline order. They collapse and expand with the same per-browser
  set the outline uses.
- Backlog and the sections show To-Do cards in `tasks.rank` order.
  Deferred cards follow the Deferred toggle.
- Done holds the project's Done root tasks, whatever their section, newest
  `resolved_at` first. While the Done toggle is off, it shows the last
  7 days in the user's zone, under the line "Done in the last 7 days. Show
  Done to see the rest." With the toggle on, it shows all of them. A daily
  repeating task leaves 365 occurrences a year, so the column is never
  unbounded by default.
- Backlog and Done are always present, even when empty, and each has a
  drop target with a minimum height. An empty section keeps its column too.
- A card shows what a task row shows: the checkbox, the title, the flag,
  effective Planned and Due, tags, the repeat mark, and a subtask count
  (`ngettext`). Enter opens the inspector.
- The board does not linger a completed card in its old column. The card
  goes to Done straight away, and Check there reopens it.
- Done cannot be reordered. A card dropped on it goes to the top, as the
  newest completed, and a drag within Done does nothing.
- The board scrolls horizontally inside its own region. On a phone the
  columns snap, and the page itself never scrolls sideways.

#### The list

A project without sections is unchanged. A project with sections shows a
**Backlog** heading, then one heading per section. Each heading has its own
outline of roots and an add field. Empty headings stay. The checkbox
marks a task Done, as it does today. Done and Dropped tasks follow the
existing toggles and appear under their section, as they appear in the
outline today. The Done column is a board-only view; the list has no Done
heading. Indent,
outdent, and reorder work inside one heading's outline. Dragging sideways
indents, and does not move a task to another heading.

#### Moving cards

A section is a field on the task, so every move is one task command.

| Move | Write |
|---|---|
| Reorder in a column, Backlog ↔ a section, between sections | One patch of `section_id` and `rank`. |
| To Done: drop on Done, Check, or moving right from the last column | `Tasks.complete_task/3`. The section is kept. |
| Reopen: Check on a Done card, or moving left from Done | State To-Do. The card returns to its section, or to the backlog if it has none. |
| Drop a Done card on a column | One patch: state To-Do, plus `section_id` and `rank` from the drop. |
| Dropped column | Not a drop target. |

Repeating tasks behave as they do anywhere else. Completing one spawns the
next occurrence in the same section ([Recurrence](#recurrence)).

#### Sections

- **Add:** the "Add a section" button after the last section, in both
  layouts, or the key `s`. The new section goes last, and its name field
  is focused.
- **Rename:** Enter on a focused heading.
- **Reorder:** drag a heading, or press Alt-Left / Alt-Right on a focused
  heading. A heading moves only among the sections, never past Backlog or
  Done.
- **Remove:** Delete, Backspace, or `dd` on a focused heading, with no
  confirmation. The flash is "Section removed. Its tasks are in the
  backlog." The section's To-Do roots go to the end of the backlog and
  keep their relative order. Its Done and Dropped tasks lose the section
  too. No task is discarded.
- **Name:** trimmed and NFC-normalized, 1–200 characters, any character.
  Two live sections in one project may share a name. The web form refuses
  a duplicate ("is already used here"), but sync does not. If two offline
  devices both create "Doing", the project has two, and the user removes
  one. Allowing duplicates means sections need none of the merge rules
  tags have.
- **Cap:** 50 live sections per project, checked in the context: "This
  project already has as many sections as it can."

#### Adding tasks

- The page's "Add a task" and the Backlog add field append to the
  backlog.
- A section's add field appends to that section.
- `n`, and vim-style `o` / `O`, on a card add a sibling in that card's
  section. Below a card with its subtasks expanded, the new task is the
  card's first subtask (ADR 0031).
- Done has no add field. A new task is never created Done.

#### Keyboard

ADR 0031 is amended in the web PR. On a board:

| Action | Standard | Vim-style as well |
|---|---|---|
| Previous and next card | Up, Down | `k`, `j` |
| First and last card in the column | Home, End | `gg`, `G` |
| Collapse, or the previous column, or the sidebar from the first | Left | `h` |
| Expand, or the next column | Right | `l` |
| Reorder within Backlog or a section | Alt-Up, Alt-Down | `K`, `J` |
| Move the card one column (right of the last section is Done), or move a focused heading | Alt-Left, Alt-Right | `H`, `L` |
| Check | Space | `x` |
| Drop the card, or remove a focused section | Delete, Backspace | `dd` |
| Flag | `f` | |
| New card below, above | `n` | `o`, `O` |
| Inspector, or rename a focused heading | Enter | |
| Add a section | `s` | `s` |

- Tab moves browser focus on a board. It does not indent.
- On a Done card, Alt-Left / `H` is the reopen above. It may land in a
  column that is not next to Done.
- In list layout, each heading's outline keeps the outline keys, `H` /
  `L` included. `s` adds a section on any project page.
- The focus stops are cards and headings, so an empty column can be
  reached through its heading.
- A move is announced in an `aria-live` region and in the flash.

`s` replaces the earlier draft's `\`, which takes Option-Shift-7 on a
Danish Mac keyboard.

### Data model

```sql
ALTER TABLE projects
  ADD COLUMN layout text NOT NULL DEFAULT 'list',
  ADD CONSTRAINT projects_layout CHECK (layout IN ('list', 'board'));

CREATE TABLE sections (
  id uuid PRIMARY KEY DEFAULT uuidv7(),
  user_id uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  project_id uuid NOT NULL,
  name text NOT NULL CHECK (name <> ''),
  rank text COLLATE "C" NOT NULL,
  discarded_at timestamp(0),
  inserted_at timestamp(0) NOT NULL,
  updated_at timestamp(0) NOT NULL,
  CONSTRAINT sections_id_project_id_key UNIQUE (id, project_id),
  CONSTRAINT sections_project_id_fkey
    FOREIGN KEY (project_id, user_id) REFERENCES projects (id, user_id)
);

CREATE INDEX sections_project_id_rank_index
  ON sections (project_id, rank) WHERE discarded_at IS NULL;

ALTER TABLE tasks
  ADD COLUMN section_id uuid,
  ADD CONSTRAINT tasks_section_root
    CHECK (section_id IS NULL OR (parent_id IS NULL AND project_id IS NOT NULL)),
  ADD CONSTRAINT tasks_section_id_fkey
    FOREIGN KEY (section_id, project_id) REFERENCES sections (id, project_id);

CREATE INDEX tasks_section_id_index
  ON tasks (section_id) WHERE section_id IS NOT NULL;
```

The database holds the invariants:

- **The section belongs to the task's project.** The composite foreign key
  enforces it. The check supplies the non-null `project_id`, without which
  a `MATCH SIMPLE` key would not be enforced.
- **Only a root task of a project is filed.** The check enforces it. An
  inbox task has no project, so the check covers it too.

`section_id` is nullable and has no default, so adding it does not
rewrite `tasks`. No backfill is needed.

Writers keep `section_id` consistent:

- **The server clears it** whenever a write makes the task stop being a
  root of that project: indent, a move to another project, to the Inbox,
  or to No project, and a patch of `parent_id`, `project_id`, or `inbox`.
  It does this whatever the client sent, so an old client that has never
  heard of the field cannot trip the foreign key.
- **Outdent** to the top level takes the parent's section.
- **Filing** into a discarded section is refused. A read treats a
  discarded section as the backlog, in case a sync race leaves one behind.
- **The sibling group:** `Tasks.Outline.group/1` adds `section_id` for a
  project root, and the group query compares it with `IS NOT DISTINCT
  FROM`. In a project without sections every root has none, so today's
  order is unchanged. Subtask groups do not change.
- **`create_task/4`** accepts `section_id`. The default rank is computed
  in that section's group.

### Recurrence

ADR 0007's copy list gains the section:

- **A repeating task:** the next occurrence lands in the latest's section,
  or the backlog if that section is gone, right after the latest.
  Subtasks have no section.
- **A repeating project:** the next project copies `layout` explicitly,
  because a changeset default would reset it. It copies each live section
  with the id `Uuid.v5(new_project_id, source_section_id)`, the same rule
  copied tasks use, so a replay names the same rows. Copied root tasks
  take the matching new section.

The AGENTS.md recurrence bullet gains "section" in PR 2, with the code.

### Sync

- **New entity `section`.**
  - Pull: `id`, `project_id`, `name`, `rank`, `discarded_at`,
    `inserted_at`, `updated_at`.
  - Client fields on insert: `name`, `project_id`, `rank`. On patch:
    `name`, `rank`.
  - A discard patch goes to `delete/4`, which calls
    `Sections.delete_section/3`. That function clears the tasks through
    cascades under the same command.
  - `Changes.fetch/3` and `Push.@schemas` gain the entity.
- **`task`** gains `section_id`, in the pull fields and in the client
  fields. **`project`** gains `layout`. A pushed task patch whose section
  belongs to another project, or is discarded, is `invalid`.
- **Apply order.** Elixir `@entities` and Rust `Entity::ALL` disagree
  today. Both become `user_preferences`, `recurrence_series`,
  `project_folder`, `project`, `section`, `tag`, `task`, `task_tag`,
  `project_tag`. `sync_test.exs` sorts the lists before comparing them, so
  an unsorted assertion is added on both sides.
- **Old clients** skip the unknown entity and the unknown columns. Their
  moves still work, because the server clears the section.
- **Replica:** the `sections` table, `tasks.section_id`, and
  `projects.layout`, with a schema bump that sets `needs_snapshot`, as the
  flagged column did. A card move is one task patch. No terminal or iOS
  screen in v1.
- **Capture extensions** only insert inbox tasks, and they are unchanged.
- **Order of release:** the server ships before any client release whose
  replica writes sections.

### Import from Todoist (its own PR)

- A section on an imported project becomes a section, and the project
  gets layout `list`, so headings appear but nobody is switched to columns
  without asking.
- A root task in a section is filed there. A subtask or an inbox task
  with a section keeps the **Missing section** problem.
- Order comes from the snapshot's order field when it has one, or else
  the array index.
- `import_item_kind` gains `'section'`. Postgres cannot drop an enum
  value, so the down migration leaves it.
- On re-import, a section's name is a merge field. A task's `section_id`
  joins the location group in `Imports.Merge` (`inbox project_id
  section_id`), so a move the user made wins.
- A hand-made section with the same name is reused and not renamed.
- `preview_note/1` goes through Gettext, with a sentence that no longer
  says sections are dropped.

OmniFocus action groups stay parent tasks.

### Text

Every string goes through Gettext as a whole sentence (ADR 0028):

- "List", "Board"
- "Backlog", "Done", "Dropped"
- "Add a section", "Add a task"
- "Moved to %{name}.", "Moved to the backlog.", "Moved to Done.",
  "Reopened."
- "Section removed. Its tasks are in the backlog."
- "This project already has as many sections as it can."
- "Done in the last 7 days. Show Done to see the rest."
- `ngettext("%{count} subtask", "%{count} subtasks", count)`

### Tests

- **Constraints:** a section from another project, a filed subtask, and a
  filed inbox task are each rejected by the database.
- **Clearing:** indent, a move to another location, and an old-style
  patch without `section_id` clear the section. Outdent adopts the
  parent's section.
- **Order:** a project without sections keeps today's sibling order.
  Alt-Up on a board stays in its column.
- **Section removal:** removing a section appends its To-Do roots to the
  backlog in order and clears its Done and Dropped tasks. The same holds
  from a push that discards the section.
- **Completing and reopening:** completing keeps the section. Reopening
  returns the task to its section, or to the backlog. Dropping a Done card
  on a column is one command.
- **Done column:** it shows the last 7 days with the toggle off and
  everything with it on.
- **Recurrence:** a repeating task stays in its section, and a repeating
  project copies its layout, its sections, and its filing.
- **Sync:** pull and push of `section`, the `section_id` checks, the
  apply order on both sides, and replica pull and merge.

### Alternatives considered

- **One placement table for projects and tags.** It needs two encodings
  of "no section", deferred triggers on two tables, a link-row sync entity
  with derived ids, and a two-write move that must be made atomic. A
  column on `tasks` gives a real foreign key and one-patch moves. Tags can
  have their own table when they come.
- **Root tasks as headings.** A heading would be a task with a state.
  Completing it would resolve its children, and it would appear in Open
  tasks and the agenda unless every view special-cased it.
- **Columns from existing data.** Columns of states alone are a status
  enum (ADR 0008). Date columns are the agenda. Child tags do not
  partition a project.
- **A board on-switch separate from the layout.** It creates a third
  state, a project whose sections exist but are hidden, and with it sibling
  rules that depend on the switch.
- **Layout in a preference or the visibility cookie.** The layout is
  chosen per project and should follow the project to other devices.

## Consequences

- Projects gain a `layout` column, a `sections` table, and
  `tasks.section_id`. The section-scoped sibling group changes nothing for
  a project without sections.
- A new synced entity, `section`, and one new task field. The Elixir and
  Rust apply orders are aligned in the same change.
- ADR 0031 is amended when the board keys ship. ADR 0007's copy list gains
  the section.
- Tag boards need their own placement table later. Project boards do not
  change for them.

### Tag boards, later

Still a goal. A task has one project but many tags, so a tag board cannot
live on a task column. It needs a placement table (task, tag, section,
rank) and an order of its own, because writing `tasks.rank` from a tag
board would reorder the project. Project boards keep `tasks.section_id`
when that arrives: there a card's place is the outline's own order, the
foreign key keeps it in its project, and a move is one patch. A board read
hides the difference from the page. Questions to settle then:

- Which tagged subtasks become cards.
- Where an unranked card sorts in a ranked column.
- Whether a placement survives untagging the task.
- What a tag merge does to sections.

### PR plan

| # | PR | Changelog |
|---|---|---|
| 1 | This ADR. AGENTS.md: the ADR row and the vocabulary rows (Section, Backlog). | `no changelog` |
| 2 | The migration, `Marskal.Sections`, the task writers and the sibling group, sync and the apply-order alignment, the recurrence copy, and tests. AGENTS.md: the recurrence copy list and the section rules. | `no changelog` |
| 3 | The web board and the list headings, and the ADR 0031 amendment. | Web, Added: "A project can be drawn as a board, with sections you name, which are headings in the list." |
| 4 | The replica: schema, pull, and the move operation. | `no changelog` |
| 5 | Import Todoist sections. | Web, Changed: "Todoist sections come in as sections on the project, instead of an import problem." |

Follow-ups: section headings in the terminal's project output, an iOS
board, and tag boards.
