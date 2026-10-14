# 0023. User preferences

## Status

Accepted

## Context

The user's timezone was a column on `users`, and the week start
(ADR 0007) would have been the next. More preferences will follow. `users`
is the sign-in row, managed by the `phx.gen.auth` code, and it does not
sync: a pull only copied the timezone into its `user` block, which a
client cannot write. A client that changes a preference offline needs the
same field patches, command ids, and change feed as every other row
(ADR 0014, ADR 0019).

## Decision

- Preferences live in **`user_preferences`**, one row per user, keyed by
  `user_id`. It has no id of its own. A trigger on `users` makes the row
  with the user, so every user has one.
- Each preference is a **typed column** with its own default and `CHECK`,
  not a `jsonb` document: the database checks the values, and two devices
  that change different preferences offline both land, field by field.
- The row syncs as the entity **`user_preferences`**. Its `id` on the wire
  is the user id. A client only patches it. An insert or a `discarded_at`
  patch is refused. It lives as long as the user, so it has no
  `discarded_at` and never needs a tombstone. The columns a client may
  write are `client_fields/1` on the schema.
- The pull's `user` block keeps `timezone`, read from the row, for clients
  from before the table. Later preferences stay on the row.
- Server code reads the row through `Marskal.Accounts.preferences/1`. The
  session and the API token load it with the user.
- A new preference is a column on this table, a migration on the server
  and in the client's local schema, and a name in that allow-list. A
  column added for clients that already pulled asks for a snapshot. What
  the preference means lives with the feature, in its own ADR when the
  choice is hard to reverse.

## Consequences

- `users.timezone` is gone; the migration copies it over.
- An offline client's local database gets the table, and its next pull is
  a snapshot, since the row predates every cursor.
- A preference that another row depends on is copied onto that row when
  it is made, as `week_start` is onto a series, so changing the preference
  later does not change what is already there.
