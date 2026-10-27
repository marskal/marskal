# 0034. Built-in collation (`PG_UNICODE_FAST`)

## Status

Accepted

Refines [ADR 0002](0002-single-postgres-database.md) and the production setup
of [ADR 0004](0004-hosting-vps-nix.md).

## Context

The production databases were made with the cluster's default: the libc
provider, which sorts and compares text by glibc's locale rules. A NixOS
upgrade moved glibc from 2.42 to 2.44, and Postgres warned on every
connection:

```text
WARNING:  database "marskal" has a collation version mismatch
DETAIL:  The database was created using collation version 2.42, but the
operating system provides version 2.44.
```

A btree index on text is ordered by the collation it was built with. When
glibc changes that order, the index no longer matches, and a lookup can miss
a row or a unique index can let a duplicate in. The cure is a reindex of
every such database, then `ALTER DATABASE … REFRESH COLLATION VERSION`, after
every upgrade that moves glibc. On NixOS that is any channel bump.

The indexes it touches are unique ones: `users.email`, `tags.name` (any
Unicode, emoji included), `import_items (source, source_id)`, and
`users_tokens.context`. `rank` is already `COLLATE "C"`. Enums, uuids, and
timestamps have no collation.

Hardly anything here needs language-aware order from the database. Lists go
by `rank`; equality, citext's case-insensitive equality, and uniqueness need
a stable order, not a Danish one. Three queries sort by name: the project
and folder pickers (`Projects.list_open/1`, `ProjectFolders.list_all/1` and
`list_active/1`).

Alternatives considered:

- **Keep libc, reindex after upgrades.** Rejected. A step to remember on
  every upgrade, and the failure it prevents is silent.
- **ICU as the database default.** Rejected. ICU's version moves with
  nixpkgs too, so the same reindex comes back on its schedule.
- **Built-in `C.UTF-8`** (Postgres 17). Code point order, like
  `PG_UNICODE_FAST`, but simple case mapping, one character to one.
  Rejected in favour of the Unicode-correct mapping, which costs nothing
  more on Postgres 18.
- **`C`.** Rejected. Byte order like the others, but `lower()`, and with it
  citext, only knows ASCII.

## Decision

Every Marskal database uses Postgres's **built-in provider** with the
**`PG_UNICODE_FAST`** locale (Postgres 18):

```sql
CREATE DATABASE marskal
  TEMPLATE template0
  LOCALE_PROVIDER builtin
  BUILTIN_LOCALE 'PG_UNICODE_FAST';
```

- Text sorts by Unicode code point. The order is part of Postgres, not of
  glibc or ICU, so no library upgrade invalidates an index.
- Case mapping is full Unicode: `upper('ß')` is `SS`. citext compares by
  `lower()`, and `lower()` is the same in nearly every case as under the
  other locales.
- Regex character classes follow Unicode's definitions.
- This covers `marskal`, `marskal_hydra`, and in development `marskal_dev`,
  `marskal_test`, and the cluster's `template1`, so `mix ecto.create` makes
  the same kind.

A list sorted by name for the user sorts with an ICU collation named in the
query, by the user's `locale` preference (ADR 0027): `COLLATE "da-x-icu"`,
and `"und-x-icu"` for a locale without its own. The collation name comes from
a fixed map, never from input. ICU's version can change that order between
upgrades, but no index uses it, so nothing goes stale.

The NixOS module creates its two databases with these settings rather than
through `ensureDatabases`, which would inherit `template1`'s libc locale. The
module does not change the host's `initdbArgs`; the cluster may hold other
databases. `web/devenv.nix` sets `initdbArgs` to the built-in provider,
since its cluster is Marskal's alone.

## Consequences

- No reindex after a glibc or ICU upgrade, and no collation warning.
- Code point order puts `Zebra` before `apple` and `å` before `æ` and `ø`
  anywhere a query sorts by text without a `COLLATE`. Such a sort that the
  user sees takes the ICU collation above.
- Postgres can't change an existing database's provider. Aiur moves by dump
  and restore into a database made as above: a few minutes of downtime, and
  `marskal_hydra` the same way. Development clusters are made again with
  `devenv` (the dev data is seed data).
- Postgres's own Unicode tables update with major versions. That can change
  case mapping for newly assigned characters, which a major upgrade's
  reindex covers.
- Tests: a check that the test database's provider is `builtin`, so a
  cluster made the old way fails loudly; the pickers' order for a Danish
  locale.
