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

The indexes on the default collation are the unique ones on `users.email`
and `tags (user_id, parent_id, name)` — both citext, and a tag name is any
Unicode, emoji included — `import_items (user_id, source, source_id)`,
`users_tokens (context, token)` through `context`, and
`devices.consent_request_id`. Oban's indexes that include `oban_jobs.queue`,
and the text primary key `oban_peers.name`, are on it too. `rank` is already
`COLLATE "C"`. Enums, uuids, and timestamps have no collation.

Hardly anything here needs language-aware order from the database. Lists go
by `rank`; equality, citext's case-insensitive equality, and uniqueness need
a stable order, not a Danish one. One query sorts by name where the user
sees that order: `ProjectFolders.list_all/1`, the Folder select on a project
and the Inside select on a folder. `list_active/1` is loaded for the sidebar
and sorted again by `rank`. `Projects.list_open/1` orders by title; the
location list shows sidebar order (`GoTo.projects/1`), so that title order
is not on screen.

Alternatives considered:

- **Keep libc, reindex after upgrades.** Rejected. A step to remember on
  every upgrade, and the failure it prevents is silent.
- **ICU as the database default.** Rejected. ICU's version moves with
  nixpkgs too, so the same reindex comes back on its schedule, and a
  linguistic default is one language while the locale preference names
  many.
- **Built-in `C.UTF-8`** (Postgres 17). The same code-point order, and
  no more stable across a Postgres major version. Rejected in favour of
  Unicode's own rules. `C.UTF-8` keeps the character typing of glibc's
  `C.UTF-8`: simple case mapping, one character to one, and the
  POSIX-compatible character classes. `PG_UNICODE_FAST` uses Unicode's
  full case conversion and the standard character classes. Every decimal
  digit counts as a digit, and symbols are not punctuation. Under
  `C.UTF-8`, `[[:digit:]]` is ASCII `[0-9]`, because POSIX allows at
  most 20 digit characters, and `[[:punct:]]` includes symbols such as
  `©`. `lower()`, which citext uses, differs on `İ` and a word-final
  `Σ`. Danish `æ`, `ø`, and `å` match. Neither locale applies Turkish
  casing: `I` lowercases to `i` in both.
- **`C`.** Rejected. Valid UTF-8 sorts the same way, but `lower()`, and
  with it citext, only knows ASCII. Devenv's default `--locale=C` is this,
  so development today treats `Æble` and `æble` as different tags.

## Decision

Every Marskal database uses Postgres's **built-in provider** with the
**`PG_UNICODE_FAST`** locale (Postgres 18) and UTF-8:

```sql
CREATE DATABASE marskal
  TEMPLATE template0
  ENCODING 'UTF8'
  LOCALE_PROVIDER builtin
  BUILTIN_LOCALE 'PG_UNICODE_FAST';
```

- Text sorts by Unicode code point. For valid UTF-8 that is byte order.
  The order is part of Postgres, not of glibc or ICU, so no library
  upgrade invalidates an index.
- Case mapping is Unicode's full case conversion. citext compares by
  `lower()`. `lower('ß')` stays `ß`, so `ß` and `ss` remain two tags.
  `upper('ß')` is `SS`; citext does not consult it, and `casefold()`
  would merge them.
- Regex character classes are Unicode's standard set. `[[:digit:]]`
  matches every decimal digit, and `[[:punct:]]` is punctuation.
- This covers `marskal`, `marskal_hydra`, and in development `marskal_dev`,
  `marskal_test`, and the cluster's `template1`, so `mix ecto.create` makes
  the same kind.

A list sorted by name for the user sorts with an ICU collation named in
the query. The name comes from a fixed map of the `locale` preference
(ADR 0027), never from the string itself. A new locale gets a line in
the map.

| Locale | Collation |
|--------|-----------|
| `da`, `en-DK` | `"da-x-icu"` |
| the other locales (`en`, `en-150`, `en-GB`, …) | `"en-x-icu"` |

`da` and `en-DK` take Danish letter order (`æ`, `ø`, `å` after `z`):
`en-DK` is English dates with Danish names. The other preferences are
English date conventions, and they sort as English (`å` beside `a`).
ICU's version can change that order between upgrades. No index uses the
collation, so nothing goes stale; the query warns until
`ALTER COLLATION … REFRESH VERSION`.

The built-in provider sets `LC_COLLATE` and `LC_CTYPE` only. Messages,
money, numbers, and time stay on glibc. `web/devenv.nix` replaces the
default `--locale=C` — appending would keep it — with:

```text
--encoding=UTF8
--locale-provider=builtin
--builtin-locale=PG_UNICODE_FAST
--locale=C.UTF-8
```

`--locale=C.UTF-8` is the glibc locale for those other categories. On
Postgres 18, full-text parsing still follows that libc ctype. Marskal
does not use full-text search. The NixOS module creates its two
databases with the `CREATE DATABASE` above rather than through
`ensureDatabases`, which would inherit `template1`'s libc locale. The
module does not change the host's `initdbArgs`; the cluster may hold
other databases.

## Consequences

- No reindex after a glibc upgrade, and the database default does not
  warn. A major Postgres upgrade can change case mapping when its Unicode
  tables move; that upgrade's reindex covers the citext indexes.
  Code-point order does not move.
- Code point order puts `Zebra` before `apple` and `å` before `æ` and `ø`
  anywhere a query sorts by text without a `COLLATE`. The folder selects
  from `list_all/1` take the ICU collation above.
- Postgres can't change an existing database's provider. Aiur moves by
  dumping each database without `--create` and restoring into a database
  made as above. `pg_dump --create` writes the old `CREATE DATABASE` and
  comes back on libc. `marskal_hydra` the same way: a few minutes of
  downtime. Columns already `COLLATE "C"` stay `C`. Development clusters
  are made again with `devenv` (the dev data is seed data). citext values
  that `lower()` equates under `pg_unicode_fast` and treats as distinct
  today fail the unique index on restore. That is `İ`, and little else.
- A column can still take an explicit collation later. Changing the
  database default takes another dump and restore.
- Tests: the test database's provider is `builtin` and its locale is
  `PG_UNICODE_FAST`, so a cluster made the old way fails loudly. The
  folder list from `list_all/1` sorts in Danish order for `da` and
  `en-DK`, and in English order for another English locale.
