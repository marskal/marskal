# Architecture decision records

This directory holds **ADRs** — durable decisions and their context.

- **`AGENTS.md`** (repo root): short, actionable rules for day-to-day work.
- **`docs/adr/`**: why we chose something, alternatives considered, consequences.

## Index

| ADR | Title | Status |
|-----|--------|--------|
| [0001](0001-record-architecture-decisions.md) | Record architecture decisions | Accepted |
| [0002](0002-single-postgres-database.md) | Single PostgreSQL app database | Accepted |
| [0003](0003-rails-auth-and-sharing.md) | Rails auth, multi-user, folder sharing | Accepted |
| [0004](0004-hosting-vps-nix.md) | VPS hosting (Nix); local = development | Accepted |
| [0005](0005-soft-gtd-nested-tags.md) | Soft-GTD and nested tags | Accepted |
| [0006](0006-task-defer-planned-due.md) | Defer, Planned, Due (tasks & projects) | Accepted |
| [0007](0007-recurrence.md) | Recurrence (anchor + interval rules) | Accepted |
| [0008](0008-task-states.md) | Task & project states (To-Do, Done, Dropped) | Accepted |
| [0009](0009-structure-outliner-and-folders.md) | Nested tasks, flat projects, project folders | Accepted |
| [0010](0010-task-lists-and-phase1-defaults.md) | Task model, inbox boolean, Phase 1 defaults | Accepted; inbox amended by [0017](0017-inbox-location.md) |
| [0011](0011-uuidv7-primary-keys.md) | UUIDv7 primary keys | Accepted |
| [0012](0012-viewcomponent-scoped-css.md) | ViewComponent widgets with CSS `@scope` | Accepted; widgets superseded at the port by [0016](0016-elixir-phoenix-web.md) |
| [0013](0013-import-framework.md) | Import framework (file and Todoist OAuth) | Accepted |
| [0014](0014-offline-sync.md) | Offline sync (field patches, change feed) | Accepted; client set amended by [0018](0018-rust-client-sync-library.md) |
| [0015](0015-repository-layout.md) | Repository layout (web app, future clients) | Accepted; sharing amended by [0018](0018-rust-client-sync-library.md) |
| [0016](0016-elixir-phoenix-web.md) | Elixir and Phoenix for the web app | Accepted |
| [0017](0017-inbox-location.md) | The inbox is a location beside projects | Accepted |
| [0018](0018-rust-client-sync-library.md) | Rust client sync library | Accepted |

## When to add an ADR

Write an ADR when a choice is hard to reverse, has meaningful alternatives, or would otherwise bloat `AGENTS.md` with rationale. Keep `AGENTS.md` to rules agents must follow; put narrative and tradeoffs here.

## Template

```markdown
# NNNN. Title

## Status

Accepted | Proposed | Superseded by ADR-NNNN

## Context

What problem and constraints?

## Decision

What we will do.

## Consequences

What becomes easier, harder, or required next.
```
