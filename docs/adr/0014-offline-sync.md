# 0014. Offline sync

## Status

Accepted; recurrence across a disconnect amended 2026-10-03 (the server
creates every occurrence). The protocol stands. The client set, and where the client engine
lives, are amended by [ADR 0018](0018-rust-client-sync-library.md): desktop,
Android, iOS, and an optional terminal client share one Rust library.

Settles the sync protocol deferred by [ADR 0011](0011-uuidv7-primary-keys.md).
Specifies the sibling order left open by [ADR 0009](0009-structure-outliner-and-folders.md).
Requires the per-user timezone foreseen by [ADR 0010](0010-task-lists-and-phase1-defaults.md).

Does **not** choose the web framework. The write path below is binding for the
current app and for any successor.

## Context

The web app is online. The phone is not. A shopping list has to check off and
accept a new item in a shop with no signal. Widgets and Siri Shortcuts run in
separate processes, often while the app is not open, and cannot require the
network either.

Those clients need a local database that is a cache of the same domain, plus a
queue of edits to send later. LiveView (or the current Hotwire UI) is just the
online client of the same operations. There is no production data to migrate.

ADR 0011 already allows a client to mint a primary key. That only removes the
allocator. It does not say what happens when the laptop renames an item while
the phone, offline, checks it off — a whole-row save from either side destroys
the other edit.

Alternatives considered:

- **Offline web** (service worker, browser database). Rejected. A second offline
  stack, and it does not serve widgets or Siri.
- **Whole-row last-write-wins.** Rejected. The supermarket case loses either the
  check-off or the rename.
- **CRDTs.** Rejected. A personal task list has a handful of devices. Field
  patches are enough, and a CRDT would be a second model to port to Swift.
- **LiveView as the native UI.** Rejected. Widgets and Shortcuts need a local
  store, and the server-driven native project that would have avoided one is
  not a path we can take.
- **Integer sibling positions renumbered on the server.** Rejected. An offline
  reorder cannot allocate a free integer without a round-trip.

## Decision

### Clients

| Client | When | Authority while offline |
|--------|------|-------------------------|
| **Web** | Now | None. It talks to the server. |
| **iOS app, widget, Siri Shortcuts** | Later | The on-device database for rows it already has |

[ADR 0018](0018-rust-client-sync-library.md) adds the other offline clients: a
desktop app, Android, and an optional terminal UI. Each trusts its own
on-device database the same way, through one shared Rust engine rather than a
port per shell.

The web app does not grow an offline cache. The phone, the widget, and
Shortcuts share one local database. They apply the same operations as the
server. They do not call the server themselves in order to render or to capture.

Import, folder sharing, and permission checks stay on the server. The phone
edits only what a previous sync made visible. If a later pull says a row is no
longer visible, the phone drops it locally.

### Writes are field patches

A user action changes the fields it means to change. Checking an item off writes
`state`. Renaming writes `title`. It does not write the rest of the row back.

Every accepted action has a **command id** (UUID). The server stores it and
ignores a replay: same id, success, no second apply. The web app generates the
id. A later phone sends its own.

The server merges **per field**, in the order it receives commands:

- Different fields both survive (check-off and rename).
- The same field: the later command wins.
- **Discard wins.** Once `discarded_at` is set, later patches to that row are
  ignored. There is no silent revive. The exception is a **tag link row**
  (task↔tag, project↔tag): whether the link exists is its only content, so
  `discarded_at` there is an ordinary field and the later command wins
  (ADR 0005).
- **`resolved_at` is first-write.** The first accepted transition of a task to
  Done or Dropped fixes it. A later resolve does not move it.

Do not use the client clock as the ordinary merge key. Receive order is the
merge clock. The one place a client timestamp is input is `resolved_at`, and
only inside a skew window: if the phone's timestamp is more than **2 minutes**
ahead of receipt or more than **48 hours** behind it, the server uses receipt
time instead.

Pending local edits are not pushed as a full row. On pull, the phone keeps a
field it still has a pending patch for, and takes the server value for every
other field.

### Change feed

Each accepted command appends one row to a **change feed**:

- **Cursor:** `bigint GENERATED ALWAYS AS IDENTITY`. Clients do not mint
  cursors, and an explicit id is rejected. This is not a domain primary key.
  UUIDv7 is the default for those (ADR 0011); a server-only counter is an
  identity column, not a `bigserial` or a hand-rolled sequence.
- **Command id:** unique.
- **Entity type and id.**
- The patch, for debugging and for tests. Pull may return the patch or the
  current row; the client's merge rule above is the same either way.

A new device does not walk history. Its first sync is a **snapshot** of the
rows visible to that user, stamped with the current maximum cursor. After that
it pulls `cursor > N`.

The pull predicate is **visible to this user**, not `user_id = viewer`. Until
sharing ships, visible means owner (ADR 0003). Record each change once, against
the entity. Do not fan a copy out per device or per future member. A new member
gets a snapshot, then the incremental feed.

### Identity, discard, order

- Domain primary keys stay UUIDv7, with `DEFAULT uuidv7()` and an explicit id
  allowed (ADR 0011). The phone mints before insert. No parallel `client_id`.
- Synced rows are not hard-deleted. **Done** and **Dropped** stay, as already
  required. A real removal sets `discarded_at` so the feed can carry the
  tombstone. Join rows (task↔tag, project↔tag) have their own UUID and their
  own tombstone. That UUID is v5 of the pair (ADR 0005), so two devices
  tagging the same task offline produce one row.
- **Sibling order is a fractional rank** (a string the client can place
  strictly between the two neighbors it already has). The server does not
  renumber siblings on an ordinary insert. A rebalance, if one is ever needed,
  is itself a set of synced rank patches. The same rule applies if projects or
  folders later gain manual order.

### Duplicate tags from offline devices

Tag names are unique per parent (ADR 0005). Two devices offline can each
create `Waiting` at the root. The server keeps the one it received first. When
it receives the second:

- It stores the second tag already discarded, with `merged_into_id` pointing at
  the first, and appends that to the feed.
- It rewrites that tag's link rows onto the first tag. Each rewritten link
  takes the v5 id of the new pair, and the old link row is discarded.
- It moves the second tag's children under the first, merging again where a
  child name clashes.
- A later command naming the merged tag, as a parent or in a link, is applied
  to the tag it was merged into.

A client that pulls a tag with `merged_into_id` repoints its local references
the same way and drops its own copy. A rename or reparent that clashes arrives
as the same kind of merge.

### Derived data is not synced

These are functions of synced fields. Either side recomputes them after
applying patches. A client value for them is not authoritative.

- Folder and tag `parent_path`
- A task's **effective tags** (task tags ∪ project tags, ADR 0005)

### Recurrence across a disconnect

Amended 2026-10-03: **the server creates every occurrence**. Clients do not
spawn, even provisionally; they get new occurrences on pull.

The rule stays structured data on the series (ADR 0007). "Next anchor" is a
**pure function** of the rule, the mode, the previous anchor, the resolution
time (on completion only), and the user's timezone. It lives in Elixir only.
Do not bury the calendar math inside a controller or a LiveView.

Offline, this costs little. A regular series always has one occurrence
scheduled after now (ADR 0007), so the client already holds the next one. An
on-completion series' next occurrence appears at the first sync after the
completion; it is usually dated days ahead. In return no client row is ever
replaced or lost, and only the server writes rule-created rows.

A client may still join a task to a series as its first occurrence. That is
the user's act, not the rule's, and the task keeps its v7 id.

**Occurrence ids for rows the rule creates are UUIDv5**, not v7. This is the
one exception to ADR 0011's "new domain keys are v7." A generator run and a
completion that reach the same slot at once name the same row.

- **Namespace:** `a5c0ffee-0014-5000-8000-000000000014`
- **Name (UTF-8):** `{series_id}|{anchor}`
- `series_id` is the canonical lowercase UUID.
- `anchor` is UTC, `YYYY-MM-DDTHH:MM:SS.ffffffZ`, fractional seconds always six
  digits.

**On completion.** The next anchor comes from the server's clamped
`resolved_at`, applied when the completion syncs.

**Regular.** The server's generator creates each occurrence when the previous
slot passes.

### Timezone

Store an IANA timezone on the user, among their preferences (ADR 0023).
Default **`Europe/Copenhagen`** until they change it.

- Recurrence calendar math uses the **stored** zone, so a weekly rule does not
  follow the phone across a travel day.
- The phone's "today" (agenda, widget) uses the **device** zone, so a list in
  another country is that country's day. The web agenda uses the stored zone.

### What syncs

Tasks (including occurrences), projects, project folders, tags, tag join rows,
recurrence series, and the user's preferences, timezone included (ADR 0023).
Sessions do not. Import batches do
not; the rows an import created sync as ordinary entities.

## Consequences

- New domain writes go through a field-patch operation that appends the feed.
  Do not add a whole-row update path beside it. The feed exists before the
  phone does, or the first native client has nothing trustworthy to pull.
- Schema grows a change feed (`bigint GENERATED ALWAYS AS IDENTITY` cursor,
  unique command id),
  `discarded_at` on synced domain tables (tags and their link rows first, with
  the tags slice), a fractional rank on task siblings,
  and the user's timezone (not null, default `Europe/Copenhagen`; in
  `user_preferences` since ADR 0023).
- `parent_path` stays as a cache maintained in application code. It is not a
  column the client may correct.
- Recurrence math has one implementation, in Elixir. The Rust client library
  stores series and occurrences and does not spawn (amended 2026-10-03).
- Tests that lock this ADR: different fields merge; same field, later command
  wins; command replay is a no-op; discard beats a stale patch; `resolved_at`
  stays on the first resolve and clamps outside the skew window; a client
  UUIDv7 round-trips; a rank can be allocated between two neighbors;
  an occurrence id is v5 of its series and slot;
  pull leaves dirty local fields alone; pull uses visibility, not
  `user_id = viewer`.
- The acceptance scenario: while the phone is offline it checks one item off
  and adds another; the laptop renames a third; after sync, all three results
  are on both sides, and a widget could have shown the remaining count from
  the local rows alone.
- iOS, when it happens: one database in an App Group, shared by the app, the
  widget extension, and the Shortcuts / App Intents extension; a pending-patch
  queue; sync HTTP, device auth, and push are part of that work, not of the
  web app. Shortcuts call the same operations (add to Inbox, add to a project,
  complete, drop, read a project's open tasks).
- Do not build an offline mode in the browser.
- Tombstones and change rows are not kept forever. For space, and because a
  discarded row and its patches still hold what the user wrote, a later purge
  hard-deletes discarded rows and change-feed rows older than a retention
  window. A client whose cursor is older than the window gets a fresh
  snapshot instead of the incremental feed, so the purge never leaves a
  device with a gap it cannot see. The window, and how it interacts with
  account deletion and data export, are decided when the purge is built.
  Not built yet.
