# 0019. Sync API and OAuth sign-in

## Status

Accepted

Sign-in is replaced by [ADR 0021](0021-ory-hydra-authorization-server.md):
Ory Hydra is the authorization server, and the web app its login, consent,
and device verification UI. The sync API below is unchanged.

Specifies the wire format and the client credentials that
[ADR 0014](0014-offline-sync.md) leaves open. The merge rules there are
unchanged. The engine that calls this API is the Rust library of
[ADR 0018](0018-rust-client-sync-library.md).

## Context

ADR 0014 says what a command does and how the server merges it. It does not
say how a client signs in, what a push or a pull looks like on the wire, or
what a client does with a command the server refuses.

The web app signs in with email and password and keeps a session cookie
(ADR 0003, ADR 0016). An offline client has no cookie jar to speak of, runs
for months between sign-ins, and may be a terminal with no browser of its own.
It still has to be revocable one device at a time.

The first clients are the terminal program (ADR 0020) and local agents that
run it. Later ones may be phones, a desktop app, and hosted agents. A hosted
agent cannot run a local program. It reaches the server through a remote MCP
endpoint, and MCP authorizes those with OAuth 2.1: the authorization code
grant with PKCE, and client registration.

`Marskal.Changes.apply/4` takes an Elixir function. Nothing yet turns a
client's field patch into a domain write, or limits which fields a client may
write.

Alternatives considered:

- **Email and password in the client.** Rejected. Every client handles the
  password, and a later second factor, or a passkey, has to be rebuilt in each.
- **A token pasted from the web settings page.** Rejected. Copying a secret
  through the clipboard is the step people get wrong, and the device grant
  costs little more.
- **Custom long-lived device tokens.** Rejected. They work for the terminal,
  and are a dead end for MCP and any third-party client. They have no scopes,
  and a leaked one works until someone notices.
- **The whole of OAuth 2.1 now** (authorization code, dynamic registration, a
  consent screen). Deferred. No client uses them yet. Dynamic registration is
  an open endpoint that lets anyone name a client, and it should not exist
  before a client needs it.
- **JWT access tokens.** Rejected. One server is both issuer and resource
  server. Opaque tokens revoke at once and need no signing keys.
- **High-level verbs on the wire** (`complete`, `move`). Rejected. The feed
  already records field patches, the merge is per field, and a verb would need
  its own replay rule.

## Decision

### Sign-in is OAuth 2.1

The web app is an **OAuth 2.1 authorization server** and the sync API is its
resource server. The first slice implements only what the terminal client
needs. The tables and the token rules are those of the full spec, so the
authorization code grant and registration are additions, not a migration.

**Now:**

- **Metadata** at `/.well-known/oauth-authorization-server` (RFC 8414).
- **Device authorization grant** (RFC 8628) at `POST /oauth/device_authorization`.
- **Token endpoint** `POST /oauth/token` for the `device_code` and
  `refresh_token` grants.
- **Revocation** at `POST /oauth/revoke` (RFC 7009), used by `marskal logout`.
- **One pre-registered public client**, `marskal`, without a secret, created
  by a migration.

**Later**, when a hosted agent or a third-party client needs it: the
authorization code grant with PKCE, a consent screen, and client
registration. Then a protected-resource metadata document, so MCP clients can
find the server. Each is its own change, with an ADR amendment if it changes
anything below.

#### Device flow

1. The client posts its `client_id` and the scopes it wants. The server
   returns a `device_code` (secret), a short `user_code` (`WDJB-MJHT`: eight
   letters without vowels or look-alikes), the verification URL `/device`, an
   expiry of **10 minutes**, and a polling interval of **5 seconds**.
2. The client shows the code and the URL, and may open
   `/device?user_code=WDJB-MJHT` (`verification_uri_complete`).
3. In the browser, a signed-in user sees the client, the device name the
   client sent, and the scopes, then approves or denies. Signing in there is
   the web login, with whatever it requires.
4. The client polls the token endpoint. The answers are RFC 8628's:
   `authorization_pending`, `slow_down`, `access_denied`, `expired_token`, or
   tokens.

A pending device authorization is a server-only row. Store a hash of the
`device_code`, not the code. It is deleted once used, denied, or expired.

#### Grants and tokens

- An approval creates a **grant**: user, client, scopes, the device name, and
  when it was last used. The settings page lists grants as devices and revokes
  them. Revoking a grant revokes its tokens.
- **Access tokens** are opaque random strings, stored as a hash, valid for
  **1 hour**, sent as `Authorization: Bearer <token>`.
- **Refresh tokens** are opaque and stored as a hash. They **rotate**: each
  use returns a new one and spends the old. A spent refresh token presented
  again revokes the whole grant, since one of the two holders is not the
  device. A refresh token unused for **90 days** expires.
- A password change, or deleting the account, revokes every grant.
- Grants and tokens are not synced entities. They do not appear in the change
  feed.

#### Scopes

| Scope | Allows |
|-------|--------|
| `sync:read` | Pull |
| `sync:write` | Push |

The terminal client asks for both by default, and for `sync:read` only with
`marskal login --read-only`. A new scope is added here when an endpoint needs
it.

### Endpoints

Sync calls are under `/api/v1`, JSON, and need an access token. The OAuth
endpoints are under `/oauth`, outside the version. A breaking change to the
sync wire format is `/api/v2`, and the server keeps v1 until clients have
moved.

| Call | Scope | Purpose |
|------|-------|---------|
| `GET /api/v1/sync/pull?cursor=N` | `sync:read` | Changes after `N`; without `cursor`, a snapshot |
| `POST /api/v1/sync/push` | `sync:write` | Commands, in order |

### Values

The same encoding as a change-feed patch (`Marskal.Changes.encode_patch/1`):

- UUIDs as canonical lowercase strings.
- Timestamps as UTC ISO 8601 with `Z`.
- States and other enums as their string values (`to_do`, `done`, `dropped`).
- Ranks as strings.
- `null` clears a field.

A row on the wire has the synced fields of its entity and nothing derived.
`parent_path` and effective tags are not sent (ADR 0014).

### Pull

`GET /sync/pull` without a cursor returns a **snapshot**: every live row
visible to this user, for each synced entity type, and the cursor of the
latest change at the moment the snapshot was read. Read it in one
repeatable-read transaction, so the rows and the cursor agree. Discarded rows
are left out of a snapshot. A new device has nothing to delete.

`GET /sync/pull?cursor=N` returns, for each entity with a change after `N`,
its **current row**, tombstones included, and the cursor of the last change it
covered. At most **1000** changes per response. `more: true` means pull again
from the returned cursor.

```json
{
  "cursor": 4812,
  "snapshot": false,
  "more": false,
  "rows": {
    "task": [{ "id": "…", "title": "Milk", "state": "done", "…": "…" }],
    "tag": []
  }
}
```

The current row, not the patch, because the client's merge needs only the
server value per field (ADR 0014), and replaying patches would make the client
re-run cascades the server already ran.

A cursor is only safe if no change below it can still commit. The server
appends a user's changes one transaction at a time, under a per-user lock, so
their ids commit in order. Sharing, which makes the feed span users,
revisits this.

A snapshot reads the cursor first and the rows after, and a page ends where
it ends. So a row may arrive before a row it refers to: a task before its
project, or a row newer than the cursor. The client keeps such references
as they are, and the next pull fills them in.

A cursor the server can no longer serve, because the feed was purged past it
(ADR 0014), gets `410 Gone`. The client discards its rows, keeps its outbox,
and takes a snapshot.

Visibility is the owner until sharing. A row that stops being visible is
listed by id under `gone`, and the client drops it. Until sharing that list is
always empty.

### Push

`POST /sync/push` takes a list of at most **1000** commands; more is `413`.
The server applies them **in order**, each in its own transaction through
`Marskal.Changes.apply/4`, and stops at the first one that fails for a
reason other than its content.

```json
{
  "commands": [
    {
      "id": "0192…",
      "entity": "task",
      "entity_id": "0192…",
      "op": "insert",
      "fields": { "title": "Bread", "inbox": true, "rank": "a0V" },
      "at": "2026-10-02T09:14:03.120Z"
    }
  ]
}
```

- `op` is `insert` or `patch`. A discard is a patch of `discarded_at`. There
  is no delete.
- `fields` is the patch. Each entity has an **allow-list** of client-writable
  fields, kept in its domain context beside the changeset the web app uses. A
  field outside the list rejects the command. Derived fields, `user_id`,
  `resolved_at`, timestamps the server keeps, and `merged_into_id` are never
  on it.
- `at` is the client's clock when the user acted. The server reads it for one
  thing: `resolved_at`, inside the skew window of ADR 0014 (2 minutes ahead,
  48 hours behind). Outside the window, or without `at`, it uses receipt time.
- Server-side consequences of a command run on the server, as they do for the
  web app: a moved task takes its subtree along, a duplicate tag merges. Those
  are cascade commands with ids derived from the client's command id, so a
  replay replays them too. The client sees their effect on its next pull.

The response has one result per command, in order:

| Status | Meaning | Client action |
|--------|---------|---------------|
| `applied` | Accepted, appended to the feed | Remove from outbox |
| `noop` | Accepted, nothing changed | Remove from outbox |
| `replayed` | This command id was already applied | Remove from outbox |
| `rejected` | Invalid: unknown field, failed validation, not visible, discarded | Remove from outbox, record the reason |

A rejected command is not retried. Its fields are no longer dirty, so the
next pull overwrites them with the server's values, and the local change
disappears. The client keeps the reason so it can tell the user once.

A command not in the results, because the server stopped, or because the
request failed, stays in the outbox and is sent again. Command ids make that
safe.

A push does not return rows. Clients pull after pushing.

### Errors

- `401` with `WWW-Authenticate: Bearer error="invalid_token"`: the access
  token expired or was revoked. The client refreshes. If the refresh answers
  `invalid_grant`, it signs in again. Either way it keeps its database and
  outbox.
- `403` with `error="insufficient_scope"`: the grant lacks the scope. Not
  retried.
- `410` as above. `426` when the client's API version is no longer served.
  Anything else is retried later.

## Consequences

- Server work, before `sync/core`: the `discarded_at` tombstone on project
  folders, the `resolved_at` skew clamp, the OAuth tables (clients, device
  authorizations, grants, tokens), metadata, the device and token and
  revocation endpoints, the `/device` approval page and a devices list in
  settings, the pull endpoint, and the push endpoint with an allow-list per
  entity.
- Whether a library provides the authorization server, or the grants are
  written here, is settled when that work starts. Either way it is behind
  `Marskal.OAuth`, and the token rules above hold.
- The client table carries what the authorization code grant will need
  (client type, redirect URIs) from the start, unused until then.
- The allow-list makes the client-writable surface explicit. A new field is
  not writable by clients until it is added there.
- Tests: device flow states (pending, slow down, denied, expired, approved);
  refresh rotation, and reuse of a spent refresh token revoking the grant;
  revoked, expired, and password-changed tokens get `401`; scope enforced per
  endpoint; pull snapshot and cursor agree; incremental pull returns
  tombstones and pages; push in order, replay, `noop`, `rejected` for a
  non-allowed field and for another user's row; `resolved_at` from `at`
  inside and outside the window.
- The client library (ADR 0018) owns the outbox, the merge, and the
  rejected-command record. Shells own the HTTP, the polling, the refresh, and
  where the tokens are kept.
