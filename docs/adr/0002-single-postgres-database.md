# 0002. Single PostgreSQL app database

## Status

Accepted

## Context

Options considered for Marskal Tasks data:

- SQLite (single file or per-workspace files)
- PostgreSQL, one app database
- Central account DB + per-workspace/tenant databases (Basecamp-style multi-DB lore)

The product is a multi-user web app with personal tasks (soft-GTD) and later **shared
projects** (owner + membership), not workspace-first tenancy or local-only single-user.

## Decision

### Platform

- Use **PostgreSQL** for development and production.
- Use a **single app database** for accounts, sessions, and all product data.
- Scope multi-user data with `user_id` / memberships — **not** separate DBs per user or workspace.
- Do **not** use SQLite as the primary app store.
- Do **not** introduce org/personal-tenant database files.

Local Postgres comes from devenv (`services.postgres`); production Postgres runs on or
beside the VPS.

### Lean into modern PostgreSQL

We are not targeting lowest-common-denominator SQL. Prefer idiomatic, current PostgreSQL
features when they improve integrity or clarity.

- **Primary keys are UUIDv7**, not identity/`serial` — see [ADR 0011](0011-uuidv7-primary-keys.md).
  Domain tables use native `uuid` with `DEFAULT uuidv7()` (PostgreSQL 18). Explicit
  ids stay allowed so clients can mint keys offline.
- **Real foreign keys** on every association that is a true FK: `REFERENCES` with
  appropriate `ON DELETE` / `ON UPDATE` behavior. Do not rely on application-only
  referential integrity for core relations (`user_id`, `project_id`, tag parent, join
  tables, etc.).
- **Constraints in the database** where they encode real invariants (unique pairs,
  non-null, check constraints) — not only model validations.
- **Extensions are welcome** when they pull their weight (e.g. `pgcrypto`, `citext`,
  `pg_trgm`, …). **Constraint:** the extension must be available via **nixpkgs** (and
  thus installable in devenv and on a Nix-managed VPS) so dev and prod stay reproducible.
  Enable extensions in migrations (`enable_extension`) and document any devenv/Postgres
  package needs in `devenv.nix` when required.
- Use PostgreSQL types and features freely when they fit the domain (`text[]` for tag
  `parent_path`, partial indexes, exclusion constraints later if needed, etc.).
- Avoid `ltree` for tags specifically — see ADR 0005 (Unicode/emoji). Other extensions
  are fine under the nixpkgs rule.

## Consequences

- Shared projects are rows + memberships in one DB (simple joins and authz).
- Standard Rails + `pg` + `DATABASE_URL` deploy story.
- No connection-switching or cross-DB sharing design.
- Schema and migrations should look like **Postgres-first** design, not SQLite-portable SQL.
- Agents and humans should not avoid FKs or UUIDv7 PKs “for Rails simplicity.”
- New extensions need a nixpkgs check before adoption; no one-off server installs that
  cannot be expressed in Nix.
- If workspace-level physical isolation is ever required, that is a new ADR (and a large shift).
