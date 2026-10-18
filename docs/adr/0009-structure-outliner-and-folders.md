# 0009. Structure: nested tasks, flat projects, project folders

## Status

Accepted

## Context

Marskal Tasks should feel **outliner-like** for actionable work: break a task into
subtasks, indent/outdent, collapse trees. **Projects** are GTD-style outcomes, not
another outline level of projects-within-projects. Users still need to group many
projects (areas of life, clients, etc.) without forcing project-to-project nesting.

## Decision

### Tasks — nestable (outliner)

- Tasks form a **tree** per user (and within a project when a task belongs to one).
- A task may have a **parent task** (`parent_id`); roots have no parent.
- UI: outliner affordances — indent/outdent, expand/collapse, create child, reorder
  among siblings. Sibling order is a **fractional rank** a client can allocate
  between two neighbors ([ADR 0014](0014-offline-sync.md)), not a renumbered
  integer.
- Depth: allow practical nesting; impose a sane max depth only if needed for
  performance/UX (not a product “only 2 levels” rule unless proven necessary).
- **Subtasks are tasks**: same states (ADR 0008), same Defer/Planned/Due (ADR 0006),
  tags, recurrence rules as applicable.
- Moving a task under another preserves or reassigns project membership with clear
  rules: prefer **child inherits project of parent** when indented under a task in a
  project; moving to root may keep or clear project — define in implementation with
  least surprise (document in UI). Baseline: subtasks of a project task stay in that
  **project**.
- Completing/dropping a parent does **not** auto-resolve children unless a later
  feature offers an explicit “resolve subtree” action (default: independent states).
- List views may show flat or nested presentation; outliner is the primary structural
  model in the data.

### Projects — not nested

- **Projects cannot contain other projects.** No `parent_project_id`.
- A project is a single outcome node with tasks (possibly a task tree) under it.

### Project folders — nestable containers (+ future share unit)

- **Project folders** organize projects only (not a place for loose tasks).
- Folders **can nest** (folder tree): e.g. `Work` → `Client A`.
- A project may belong to **at most one** folder (or none = unfiled). Optional folder
  is fine.
- Folder hierarchy is for navigation/filing, not GTD “project” semantics.
- **Folder fields stay minimal:** **name** (required), **parent** (optional), and
  **state**: **Active** | **Dropped** only.
  - No Done (folders are not outcomes).
  - No Defer / Planned / Due on folders.
  - **Dropped** = archived/hidden from default folder chrome; projects inside are not
    auto-resolved (they keep their own states). Activate restores the folder.
- Storage sketch: `parent_id` + `parent_path text[]` (ancestor names root→parent), same
  spirit as tags (ADR 0005), for breadcrumbs and rename/reparent cascade.
- **Sharing (ADR 0003):** folders are the **primary sharing mechanism**. Share a folder
  ⇒ access to that folder, **all descendant subfolders**, and **all projects** in that
  subtree (and their tasks). Design folder ownership and tree moves with that in mind.
- Until sharing ships: folders `belongs_to` owning user only.

### Mental model

```text
Project folders (nested)          ← share boundary (later): share folder → subtree
  └── Project (flat — never under another project)
        └── Tasks (nested outliner tree)
              └── subtasks …
```

Tags (ADR 0005) remain orthogonal: project tags inherit to tasks; folders are not tags.

## Consequences

- Schema sketch:
  - `tasks.parent_id` → tasks (nullable FK), sibling fractional rank (ADR 0014)
  - `projects` — no parent project FK
  - `project_folders`: `name`, `parent_id`, `parent_path text[]`, `state` active|dropped
  - `projects.project_folder_id` → project_folders (nullable FK)
- Real foreign keys per ADR 0002; UUIDv7 keys per ADR 0011.
- UI investment in outliner interactions is Phase 2-ish alongside projects (or thin
  nesting in Phase 1 if capture needs subtasks early — prefer not blocking Phase 1
  inbox; **nesting + folders in Phase 2** with projects).
- Queries: subtree loads, reorder, prevent cycles on task and folder parent changes.
- Tests: cycle prevention; indent into project task keeps project; folder nest; project
  cannot parent another project; (later) share cascade with ADR 0003.

## Implementation note (2026-09-29)

The move rules left open above:

- A subtask always has its parent's location (Inbox, No project, or the parent's
  project). Indenting or placing a task under another moves it, and its subtree,
  there.
- Choosing another location for a subtask takes it out from under its parent, to
  the top level of the new location. Its own subtasks go with it.
- Sibling order is `rank` among tasks with the same parent, or the same location
  at the top. New tasks go to the bottom, except the inbox, which lists newest
  first.
- Deleting a task discards its subtree.
- Completing or dropping a task, or its project, makes the open tasks below it count
  as resolved: they leave every open list, though their own state stays To-Do.
  Reopening brings them back as they were. Nothing is written to them, so this
  replaces the "independent states" default above only in how they show.

A deferred constraint trigger (`tasks_outline`) checks at commit that a live
subtask shares its parent's location, has a live parent, and is not its own
ancestor.

Views: the project and inbox pages show the outline, with collapse kept per
browser and outliner keys: Tab and Shift-Tab, or the macOS-style Cmd-] and
Cmd-[, indent and outdent; Alt-Up and Alt-Down move among siblings. Those
are the standard keymap; [ADR 0031](0031-keyboard-keymap.md) adds a Vim-style map and the
keys that complete, drop, flag, and start a new task. Open tasks
nests subtasks under their parents too (2026-10-10): the top level stays newest
first, subtasks go by rank, and rows collapse but do not move. A parent that tag
state hides shows, dimmed, above its available subtasks. Other lists stay flat
and name a subtask's parent before its title.
Rows drag by the whole row (SortableJS), from anywhere but its controls: a
press that hardly moves is a click, and on touch a hold starts the drag, so
a swipe still scrolls. The drop depth follows how far the pointer
moved sideways, one level per indent, within what the neighboring rows allow;
the subtree moves with its root.
