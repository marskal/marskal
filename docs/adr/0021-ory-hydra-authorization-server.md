# 0021. Ory Hydra as the authorization server

## Status

Accepted

Replaces how [ADR 0019](0019-sync-api-and-oauth-sign-in.md) signs clients
in: the server is Ory Hydra, not OAuth code in the web app. What ADR 0019
asks of sign-in stays: the device grant, opaque tokens, an hour's access
token, rotating refresh tokens, the two scopes, and signing out one device
at a time. The sync API is unchanged.

Amends [ADR 0002](0002-single-postgres-database.md): Hydra keeps its own
database in the same Postgres cluster. App data stays in one database.

## Context

ADR 0019 made the web app an OAuth 2.1 authorization server and built the
first slice by hand: the device grant, refresh, and revocation. More OAuth
is coming: the authorization code grant with PKCE, client registration, and
a remote MCP endpoint for hosted agents. Each adds protocol code, and each
is easy to get subtly wrong. A maintained server carries that, and its
security fixes, instead of this codebase.

The Elixir options were weighed first:

- **Boruta** is active, but one person writes nearly all of it. It stores
  access and refresh tokens in plain text, and changing that means a fork.
  It has no device grant; the request for one has been open since September
  2025 with no reply.
- **ExOauth2Provider** has not had a release since 2023.
- **Guardian** and **Ueberauth** are not authorization servers.

**Ory Hydra** is an OAuth 2.1 and OpenID Connect server in Go, maintained by
a company and widely deployed. It has had the device grant since v25.4. It
does not keep user accounts: it hands login and consent to an app over an
admin API. nixpkgs packages it.

A spike ran Hydra 26.2 from nixpkgs under devenv and checked, end to end:
the device flow handing off to the web app for the code, login, and
consent; refresh rotation, with reuse inside a grace window; introspection
carrying a claim the web app set at consent; and revoking one device's
consent killing that device's tokens and no other's.

Alternatives considered:

- **Keep the hand-written server.** Rejected. Fine for one grant, too much
  security code to own as OAuth grows.
- **Boruta.** Rejected, for the reasons above.
- **Keycloak, Zitadel, and the like.** Rejected. They want to own user
  accounts. Login stays email and password in the web app (ADR 0003,
  ADR 0016).
- **JWT access tokens from Hydra**, checked without a call. Rejected for
  now. Revoking a device would wait for its token to expire. Hydra's own
  docs advise against JWT access tokens.

## Decision

### Roles

- **Hydra** runs the OAuth protocol: device authorization, token, revocation,
  and later authorization and registration. Clients talk to it.
- **The web app** is Hydra's login, consent, and device verification UI, and
  the resource server for the sync API. Users sign in to the web app as
  today; Hydra never sees a password.

### Endpoints

In production Hydra's public port sits behind the same host as the web app.
The reverse proxy sends `/oauth2/*`, `/.well-known/oauth-authorization-server`,
`/.well-known/openid-configuration`, and `/.well-known/jwks.json` to it. Hydra
serves the RFC 8414 metadata itself, so a client needs only the server's URL.
Its admin port listens on localhost only and is never proxied.

### The device flow

1. The client posts to Hydra's device endpoint and shows the code.
2. Hydra sends the browser to the web app's `/device` with a
   `device_challenge`. The signed-in user confirms the code there, and the web
   app accepts it over the admin API.
3. Hydra sends the browser to the web app's login endpoint. The web app
   accepts it with the user's id as the subject, sending the user through
   ordinary login first if needed. When Hydra says to skip, because it
   already knows the login, the web app accepts with that same subject and
   asks nothing.
4. Hydra sends the browser to the consent endpoint. The web app shows the
   client and the scopes, and asks for a name for the device, since the
   device grant carries none. On Allow it records a **device** and accepts
   consent with the device's id in the access token's extra claims.
5. Hydra sends the browser to `/device/done`. The client's next poll gets
   tokens.

### Tokens and scopes

- Opaque tokens. Hydra stores signatures, not the tokens.
- Access tokens last **1 hour**, refresh tokens **90 days**.
- Refresh tokens rotate. A used one stays valid for **30 seconds**, so the
  command line and a terminal UI refreshing at once (ADR 0020) do not sign
  the device out. Reuse after that window revokes the chain.
- Scopes: `sync:read` and `sync:write` as in ADR 0019, plus
  `offline_access`, which Hydra requires for a refresh token.
- One OAuth client per application, public, from a file in
  `priv/hydra/clients`, created by the deployment and by devenv,
  idempotently. Every copy of an application, on every device, signs in as
  that one client; the devices table tells the copies apart. The terminal
  program is `marskal-terminal`, with the device and refresh grants. Another
  application, such as a phone app with the authorization code grant, gets
  its own.

### Devices

The web app keeps a `devices` table: owner, name, Hydra's consent request id,
when it was approved and last used. Settings lists them.

The sync API introspects each bearer token over Hydra's admin API. A request
passes when the token is active, its subject is a user, it has the scope, and
its device is still in the table. Signing a device out revokes its consent in
Hydra, which revokes its tokens, and deletes the row. A password change
revokes every consent of that user.

### Running it

- **Development:** devenv runs Hydra (`processes.hydra`), with
  `web/config/hydra.dev.yml`, public on 8276 and admin on 8277, and its
  database `marskal_hydra`.
- **Production:** the web app's NixOS module adds a Hydra service from
  nixpkgs, which runs its migrations before it starts, with its system
  secret from the environment file (ADR 0004). nixpkgs has no Hydra module;
  ours is small.
- Hydra does not prune its own tables. `hydra janitor` runs on a timer in
  production and as a devenv task, to delete expired tokens and finished
  login, consent, and device requests.

## Consequences

- The web app's hand-written OAuth goes: its tables, `Marskal.OAuth`, and the
  `/oauth/*` endpoints of ADR 0019. `/device` stays, as Hydra's verification
  UI. The sync API keeps its paths, its scopes, and its errors.
- One more process in development and production, and one more database in
  the cluster. Its upgrades follow nixpkgs. Ory sells an enterprise build with
  scheduled security fixes; the open-source build gets them with community
  releases, which have come one to three times a year. An urgent fix that is
  not released yet can be built from source through Nix.
- Every sync request costs an introspection call to Hydra on localhost. If
  that shows up, cache an answer for a few seconds; a revoked device then
  lasts at most that long.
- The terminal client changes little: it asks for `offline_access`, finds the
  endpoints from metadata, and revokes at Hydra on logout.
- The authorization code grant, client registration, and remote MCP become
  Hydra configuration plus the consent screen the web app already has.
- Hydra reaches the device and consent pages with GET redirects, which
  Phoenix's CSRF protection does not cover. Confirming a code and allowing a
  device happen on a form post or a LiveView event, never on page load.
- Tests: the login, consent, and device endpoints against Hydra's admin API
  (stubbed in unit tests, Hydra itself in an end-to-end run); introspection
  failures giving `401` and `403`; a revoked device refused at once.
