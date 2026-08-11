# 0001. Record architecture decisions

## Status

Accepted

## Context

Product and stack choices for Marskal Tasks accumulated a lot of rationale (database
shape, auth, hosting, soft-GTD/tags). Putting all of that in `AGENTS.md` makes the
file hard to scan and mixes “do this” with “why we decided this.”

## Decision

- Keep **`AGENTS.md`** slim: vocabulary, phases, and enforceable conventions.
- Record significant decisions as **ADRs** under `docs/adr/`.
- Agents and humans should treat accepted ADRs as binding unless superseded.

## Consequences

- New architectural choices get an ADR (or an update/supersession), not a long essay in `AGENTS.md`.
- `AGENTS.md` links to this directory for depth.
