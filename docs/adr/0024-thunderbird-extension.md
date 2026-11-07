# 0024. Thunderbird extension

## Status

Accepted

A capture-only client. It is not an offline client of
[ADR 0018](0018-rust-client-sync-library.md) and does not link `sync/core`.
It signs in as [ADR 0021](0021-ory-hydra-authorization-server.md) describes
and writes through the push of [ADR 0019](0019-sync-api-and-oauth-sign-in.md).

## Context

Much work arrives as mail. Capturing it today means retyping the subject
into the inbox, and the task loses its way back to the message.

Two ways in were weighed:

- **A Thunderbird extension.** One click on a message on the desktop, where
  most mail is handled. It can read the Message-ID and keep a link to the
  message.
- **A "send to inbox" address.** Works from any client, the phone included,
  but needs inbound mail on the server, a secret address per user, and
  sender checks, and the task is a copy with no link back. Deferred, not
  rejected: it suits phone capture, and may come later.

Thunderbird extensions are WebExtensions. They can use Manifest V3 and read a
message's readable text parts. Thunderbird for Android
does not run extensions.

## Decision

An extension in **`clients/thunderbird`**, Manifest V3. It supports
Thunderbird back to the **oldest supported ESR**, now 140, and no further;
the minimum version moves up when that ESR ends. TypeScript, built to plain
JavaScript; its own `devenv.nix` with Node.

It is listed on addons.thunderbird.net as **Marskal for Thunderbird**, ID
`thunderbird@marskal.app`, which never changes. Each release uploads the
`.xpi` and the committed source it builds from, since the scripts are
bundled; the listing text and privacy policy are in `LISTING.md` beside it.

### What it does

- A **button on a displayed message** opens a popup: the title, editable,
  prefilled with the subject; whether to keep the message text in the notes;
  and **Add to inbox**.
- **"Add to Marskal inbox"** in the message list's context menu adds every
  selected message at once, with no popup, and reports with a notification.
- Each message becomes one task in the **inbox** (`inbox = true`, ADR 0017),
  at the position the server gives it:

  | Field | From |
  |-------|------|
  | `title` | The subject, trimmed, at most 500 characters. Without a subject, "Mail from" and the sender |
  | `url` | `mid:` and the Message-ID (RFC 2392), so the task leads back to the message |
  | `notes` | Sender and date, then the message's plain text, cut to fit the notes limit |

  The plain text is the text part, or the HTML part converted by
  Thunderbird. Quoted replies are kept; guessing where they start loses text.

### Sign-in

- Its own public Hydra client, **`marskal-thunderbird`**, with the device and
  refresh grants, from `priv/hydra/clients` like the terminal's (ADR 0021).
- Scopes **`offline_access sync:write`**. It never pulls, so it does not ask
  to read.
- The options page takes the server's URL, **HTTPS only** (an `http://`
  address becomes `https://`), lists the mail that is sent, asks Thunderbird
  for access to that host, refuses OAuth endpoints that are not HTTPS,
  starts the device grant, and opens the verification link in the default
  browser. The user confirms the code and names the device in the web app,
  as for the terminal. Sign out revokes the refresh token at Hydra.
- Tokens are kept in the extension's local storage, in the Thunderbird
  profile. One background script does every refresh, one at a time, so the
  rotating refresh token is never used twice.

### Writing

- One `insert` command per message to `POST /api/v1/sync/push`. The extension
  makes the task id and the command id, both UUIDv7, and sends `at`.
- No local database, outbox, or pull. If the push fails, the popup says so
  and keeps the command, and **Try again** sends the same ids, so a push the
  server did get is `replayed`, not a second task. The context-menu path
  reports the failure; adding again makes new ids.
- A `rejected` result is shown with its reason.

## Consequences

- One more OAuth client file on the server. The extension asks for access to
  the server's host, and reaches Hydra because Hydra is on that host: behind
  it in production, and on `marskal.localhost` beside Phoenix in development,
  which the extension reaches only once Phoenix serves HTTPS there.
  Thunderbird's host permissions ignore the port. The consent
  page shows its name and that it can only write.
- `mid:` links open the message where the system hands `mid:` to Thunderbird
  (Thunderbird accepts `thunderbird mid:<id>`). In the web app the link shows
  but a browser may not follow it, as with `file:` (ADR 0022).
- The extension speaks the wire format of ADR 0019 itself. That is safe
  only because it sends one kind of command and reads nothing back; an
  extension that shows or edits tasks is an offline client and links the
  library, through WebAssembly or a native host.
- A later "send to inbox" address can reuse the same mapping of a message to
  a task, on the server.
- Tests: the message-to-task mapping (subject, no subject, long subject,
  Message-ID encoding, notes cut), and the push results, in Node's test
  runner.
