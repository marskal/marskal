# 0017. The inbox is a location beside projects

## Status

Accepted

Amends the inbox in [ADR 0010](0010-task-lists-and-phase1-defaults.md): the
`tasks.inbox` boolean stays, but it is no longer independent of the project,
and the Clarify action goes. The rest of ADR 0010 stands.

## Context

ADR 0010 made the inbox a boolean beside `project_id`, cleared by a Clarify
action. The two fields could disagree: a task could sit in a project and in
the inbox at once. Clarify was a step of its own, with a word that said
nothing about the inbox, and putting a task back needed a second control.

Deriving the inbox instead (no project and no tags) was tried and rejected.
A task could not wait in the inbox once it had a tag, and a task meant to
belong to nothing could never leave.

## Decision

- A task has one **location**: the **Inbox**, **No project**, or **one
  project**. The three are exclusive.
- Storage stays `tasks.inbox` plus `tasks.project_id`, with
  `CHECK (NOT inbox OR project_id IS NULL)`.
- One picker sets it: Inbox, No project, then the projects. Choosing a
  project leaves the inbox. Choosing Inbox leaves the project. Moving back
  to the inbox uses the same picker, not a separate action.
- **Tags do not affect location.** A task can be tagged while it waits in
  the inbox.
- A new task goes to the inbox, unless it is created with a project, as in a
  project view.
- The **open stream** leaves inbox tasks out (as ADR 0010 said). A task that
  belongs to no project reaches it by moving to No project.
- **Sync:** a move always patches `inbox` and `project_id` together, even when
  one of them keeps its value. A field-level merge of two offline moves then
  takes one whole location and cannot pair a project with the inbox. A
  command that asks for the inbox and a project at once is refused.
- **Import:** a source task with a project lands in that project, even if the
  source also flags it inbox. One without a project, or whose project was not
  imported, lands in the inbox.

## Consequences

- The migration moves any task that had both a project and the inbox flag to
  its project, then adds the constraint.
- No Clarify button, and no inbox checkbox. The inbox page has no action of
  its own besides done and dropped; lists keep a moved row until the user
  leaves the view.
- Project views cannot contain inbox tasks. Tag views and the untagged view
  still mark inbox tasks.
- No settings for when a task leaves the inbox. The picker makes it explicit.
