# 0030. Sync event stream

## Status

Accepted

Adds an endpoint to the sync API of
[ADR 0019](0019-sync-api-and-oauth-sign-in.md). Pull and push are
unchanged. Amends [ADR 0029](0029-ios-app.md): an open app learns of a
change from this stream, not by pulling on a timer.

## Context

An offline client pulls when it opens, after its own changes, and when the
user asks. A change made elsewhere, such as a task checked off on the web,
reached an open phone only at the next of those. Pulling every minute fixed
that slowly and at a cost: a request a minute from every open client, almost
all of them answered with nothing new.

The server already knows when a user's data changes. `Marskal.Changes`
broadcasts every accepted write on the user's PubSub topic, and the web
app's LiveViews update from it.

What a client needs is a nudge: something changed, here is the latest
cursor. The rows still come by pull, with the merge of ADR 0014.

Alternatives considered:

- **Polling.** Rejected as the way to stay current. It is late by up to its
  interval, and costs a request each time whether anything changed or not.
- **WebSocket.** Rejected. It is two-way, and nothing goes from client to
  server on it: push stays a POST. It needs the upgrade handshake and the
  proxy's support for it.
- **Phoenix Channels.** Rejected. Every client would speak the Channels
  protocol (joins, heartbeats, message references) for one kind of message,
  one way.
- **A protocol of our own over TCP or QUIC, MQTT, or gRPC streaming.**
  Rejected. Each needs another port, its own TLS and authentication, a
  broker, or generated code, for a nudge.
- **Long polling.** Rejected. A request per change, and a connection held
  between them anyway.

## Decision

**Server-Sent Events** at `GET /api/v1/sync/events`, with the bearer token
and the scope `sync:read` of the other sync endpoints.

- The response is `text/event-stream`. It starts with `retry: 5000`, then
  sends the current cursor:

  ```text
  id: 4269
  event: changed
  data: {"cursor":4269}
  ```

  The cursor is the event's id. A client that reconnects with
  `Last-Event-ID` gets an event on connect only when the cursor moved while
  it was away.
- Every write the user's topic carries leads to one event. A burst, such as
  an import, waits a quarter of a second and sends one event with the
  latest cursor.
- A comment line every 25 seconds keeps proxies from closing a quiet stream
  and shows the server a dead one.
- The token is introspected again every five minutes. A token that expired,
  or a device signed out in the web app, ends the stream. The client then
  reconnects with a fresh token, or learns it is signed out.
- The response sets `X-Accel-Buffering: no`, so nginx passes each event on
  at once without other configuration.
- One Elixir process per open stream, subscribed to the user's topic, as a
  LiveView is.

A client:

- Keeps the stream open while it shows the user's data, and closes it when
  it does not. On iOS that is while the app is in the foreground.
- Pulls on an event whose cursor is past its own. Its own push comes back as
  an event; the cursor shows there is nothing new.
- Reconnects after the `retry` delay, with `Last-Event-ID`. While the
  stream is down it pulls as before, when it opens and after its own
  changes.

## Consequences

- No polling. A change made elsewhere reaches an open client within a
  second.
- A suspended iOS app keeps no connection. A closed app and the widget learn
  of changes only through push notifications (APNs), which remain later
  work and need a paid Apple developer account.
- The terminal client's full-screen mode (ADR 0020), and a desktop or
  Android client, can use the same stream.
- A stream holds an HTTP connection and a process. A user's handful of
  devices is nothing to the server; the five-minute introspection is the
  only recurring cost.
- Tests: the first event and `Last-Event-ID`; a burst as one event; no
  event for another user's writes; the stream ending when the device is
  signed out; the scope.
