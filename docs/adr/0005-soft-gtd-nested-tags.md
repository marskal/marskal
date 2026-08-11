# 0005. Soft-GTD and nested tags

## Status

Accepted

## Context

Classic GTD uses **contexts** (`@home`, `@errands`, …). We want GTD-inspired lists and
flow without rigid orthodoxy. Organization should be flexible (people, duration,
place, energy, etc.), support **Unicode and emoji**, and allow hierarchy such as
`Person` → `Wife`, `Location` → `Home`.

Alternatives considered for hierarchy storage:

- First-class Context model — rejected (too rigid; soft-GTD).
- Postgres **`ltree`** — rejected (label charset blocks normal i18n/emoji).
- Slash-separated `text` path only — workable but separator-in-name issues.
- **`ltree`-like GENERATED path** — generated columns cannot walk `parent_id`; full
  path still needs denormalized parent data; UI will render fancy HTML anyway.
- **`parent_id` + `parent_path text[]`** — accepted.

## Decision

### Product

- **Soft-GTD:** capture → clarify → organize → reflect → engage; lists for inbox,
  next, projects, waiting, someday, plan — without enforcing full GTD dogma.
- **No** first-class Context entity or hardcoded context vocabulary.
- **Nested tags** only; many tags per entity; per-user tag trees.
- Example segments (user convention, not schema enums): `Person`/`Wife`,
  `Duration`/`Short`, `Location`/`Home`.
- Tags apply to **tasks** and **projects**.
- **Tags ship in Phase 2** (with projects & planning), not Phase 1.
- Phase 4 may polish tag UX (create-on-type, nest browsing, filters).

### Project tags and inheritance

- A **project** may have zero or more tags (same tag model as tasks).
- **Inheritance:** tags on a project **automatically apply to all tasks in that project**.
- A task’s **effective tags** = **union** of:
  - tags assigned directly on the task, and
  - tags assigned on its project (if any).
- Prefer **inheritance at read/filter time** (or equivalent), not copying project tags
  onto every task row on write — so changing project tags updates effective tags for
  all member tasks without mass rewrites. (Denormalized cache is an optional later
  optimization, not required.)
- UI may show inherited tags as such (e.g. distinct from task-only tags) when helpful.
- Filtering by a tag matches a task if the tag is in its **effective** set.
- Direct task tags remain useful for task-specific labels not shared by the whole project.
- Moving a task between projects changes inherited tags with the new project’s set.

### Storage

```text
tags
  user_id
  name              -- one segment; Unicode/emoji OK
  parent_id         -- null = root
  parent_path       -- text[]; ancestor names root→parent; {} at root
```

- Full path in app code: `parent_path + [name]` (no separate stored path column
  unless a later need appears; **no** `GENERATED ALWAYS` path).
- Create under parent: `parent_path = parent.parent_path + [parent.name]`.
- Rename/reparent (rare): cascade-update descendants’ `parent_path` in app code.
- Presentation: render hierarchy in **HTML** from segments (view concern).
- Join tables: **task ↔ tags**, **project ↔ tags** (HABTM or equivalent). Do not use `ltree`.
- Do not require duplicated project tag rows on every task for inheritance.

## Consequences

- Phase 1 stays focused on inbox and list transitions without tagging UI.
- Phase 2 adds tags on tasks **and** projects, plus inheritance in filters/display.
- Hierarchy queries use array prefix / app helpers; no `ltree` extension.
- Unicode-first tags remain viable long-term.
- Tag filter queries must join project tags for tasks that belong to a project.
