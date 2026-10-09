# 0025. Flagged tasks and projects

## Status

Accepted

## Context

Most task apps let the user mark an item as important, apart from its
dates. Of the import sources, OmniFocus flags and Todoist has priorities
1 to 4, where 4 is in effect "none". Imports carry these, and without a
home they sat in `import_items.extras`.

Graded priorities tend to drift upward until everything is top priority,
and a user who wants levels can keep them as tags.
Soft-GTD already has Due for a hard deadline, Planned for the day's work,
and tags for context and energy (ADR 0005, ADR 0006).

## Decision

- Tasks and projects get one boolean, **`flagged`**, default false. There
  are no levels.
- A flagged project flags its tasks, derived at read time. A parent task
  does not flag its subtasks, as with tags (ADR 0005).
- The flag hides nothing and defers nothing. It is shown on the row, set in
  the inspector, and has its own view: **Flagged**, the open tasks that are
  flagged by themselves or by their project, inbox included. Unavailable and
  deferred tasks are hidden there unless shown, as in the open stream.
- It syncs as an ordinary client-writable field (ADR 0014, ADR 0019).
- The next occurrence of a series copies it (ADR 0007).
- **Import:** OmniFocus flagged becomes flagged. Todoist's highest
  priority (P1 in its UI, `priority` 4 in its API) becomes flagged; P2 and
  P3 become the tags "Priority 2" and "Priority 3", so the level is not
  lost and the user can turn them into flags or drop them. P4 is nothing.

## Consequences

- One bit cannot say which of two flagged items matters more. Order within
  a project, dates, and tags do that.
- The client library's local schema gains the column, and a client asks for
  a snapshot after upgrading so it learns the flags it already pulled.
