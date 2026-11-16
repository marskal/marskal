# 0040. Client versions

## Status

Accepted

Amends [ADR 0019](0019-sync-api-and-oauth-sign-in.md): it fills in the
`426` that ADR 0019 reserved for a client the server no longer serves, and
that answer is not retried.

## Context

A client is updated when its user updates it, and the server when it is
deployed. They drift apart. ADR 0019 keeps a breaking change to the wire
format under `/api/v2`, with `/api/v1` served until clients have moved, and
reserves `426` for a client whose API version is no longer served. Nothing
says which clients those are, and the server cannot tell: only the terminal
names itself, in `User-Agent`, and the server reads nothing from it.

Not every break is a new wire format. A client release can have a bug the
server has to refuse, such as a push that writes bad values, and a change to
an entity can break the clients that pull it but not the capture
extensions, which only push inbox inserts. When the server stops serving a
client, that client's user should see why, and which version to update to,
instead of a sync that fails without a reason.

Under ADR 0038 every component carries one version, but only what changed
ships: a client skips the releases it did not change in. One minimum for
every client would lock out a client that has no release at that minimum,
with nothing for its users to install.

## Decision

- **Clients name themselves.** Every request to `/api/v1` carries
  `Marskal-Client: <client id>/<version>`, such as
  `marskal-terminal/0.3.0`. The client id is the shell's OAuth client
  (ADR 0021); the version is its release (ADR 0038). A header of its own,
  because Chromium does not let an extension set `User-Agent`, and iOS
  writes its own there.
- **The server keeps a minimum.** `MarskalWeb.ClientVersion` holds one
  default minimum version and overrides per client id. A client without an
  override, or with an id the server does not know, needs the default.
  A plug checks the header ahead of authentication on every `/api/v1`
  route, the event stream included, so an outdated client hears that
  before anything else.
- **The answer is `426`.**

  ```json
  {"error": "client_outdated", "client": "marskal-terminal",
   "minimum_version": "0.4.0",
   "message": "This server needs marskal-terminal 0.4.0 or later."}
  ```

  A client tells its user in its own words, from `error` and
  `minimum_version`; API codes are not translated (ADR 0028), and
  `message` is for a client that does not know the code. It is not
  retried, and the outbox is kept for after the update.
- **Raising a minimum.** Raise the default when a server change breaks
  clients, or one client's override when only it breaks. A minimum must be
  a version that client shipped in: a test checks that `CHANGELOG.md` has a
  section for the client's component at that version or later. A client
  that skipped those releases gets an override at its last one, if the
  change does not break it, or a release that brings it up.
- **A missing header passes.** Clients released before this one send
  none, and they could not tell their user what a `426` means: they would
  show it as one more failed sync. Refusing them buys nothing a breaking
  change would not do on its own.
- **The server names its version.** Every `/api/v1` answer carries
  `Marskal-Server: <version>`, for a client to show when it reports a
  problem, and for the opposite drift: a new client talking to an old
  server.

## Alternatives

- **The version in `User-Agent`.** Rejected: the extensions cannot set it,
  and iOS adds to it.
- **One minimum for every client.** Rejected: clients skip releases
  (ADR 0038), so a raised minimum can name a version a client never had.
- **A protocol revision instead of the release version.** A number clients
  declare, raised on each break. Rejected: it is a second version to keep
  in step, and it cannot refuse one release with a bug.
- **Only `/api/v2`.** Kept for a new wire format, but it cannot refuse an
  old client of the same format, and it does not tell the user anything.

## Consequences

- Each client sends the header on its `/api/v1` calls and shows `426` as a
  problem the user can fix: the terminal fails with `client_outdated` and
  exit code 6, iOS shows an alert once per minimum, and the extensions say
  so where they report a failed capture.
- The OAuth endpoints are Hydra's and see no check; a client that signs in
  hears it on its first sync.
- Clients do not use `Marskal-Server` yet.
