# 0029. iOS app

## Status

Accepted

The iOS shell of [ADR 0018](0018-rust-client-sync-library.md): the app, its
widget, and its App Intents. It links `sync/core` through a UniFFI wrapper
crate, `sync/ffi`. Amends ADR 0018's "Shortcuts extension": the intents run
in the app's process, not in an extension of their own. Adds a client to
[ADR 0021](0021-ory-hydra-authorization-server.md) with the authorization
code grant that ADR expected for a phone.

## Context

ADR 0018 settled the shape: a SwiftUI app in `clients/ios`, the engine in
Rust behind UniFFI, one SQLite file in an App Group shared by the app and its
extensions. What it left open is what this ADR decides.

- **Sign-in.** The two clients so far use the device grant. On a phone the
  code and the browser are on the same screen, and copying between them is
  the step people get wrong. iOS has a system sheet for a web sign-in that
  hands a redirect back to the app.
- **The boundary.** `sync/core` returns borrowed values (`World`, `&Task`),
  takes `&mut Store`, and uses `jiff` types. UniFFI exports owned records and
  objects that are `Send + Sync`.
- **The shared file.** iOS terminates a suspended app that holds a lock on a
  file in an App Group container. The widget writes to the same file.
- **Tooling.** Xcode cannot come from Nix. An `.xcodeproj` written by hand is
  a file nobody can review, and the project is not edited in Xcode.
- **Text.** ADR 0028 puts the web app's text through Gettext. Xcode's own
  route is a String Catalog.

There are no existing installs to support.

## Decision

### Platform

- **iOS 27** and later, iPhone first. The newest SwiftUI, WidgetKit, and App
  Intents, with no availability checks. The minimum moves only when a
  feature needs it.
- **Swift 6** language mode, strict concurrency. SwiftUI with Observation.
  No third-party UI libraries. A Swift package is added only when Foundation
  and the SDK have nothing that fits.
- Identifiers, under the `marskal.app` domain:

  | What | Identifier |
  |------|------------|
  | App | `app.marskal.ios` |
  | Widget extension | `app.marskal.ios.widget` |
  | App Group | `group.app.marskal` |
  | OAuth client | `marskal-ios` |
  | Redirect URI | `app.marskal.ios:/oauth/callback` |

### Layout

```text
sync/ffi/            # UniFFI wrapper crate over sync/core; builds the XCFramework
clients/ios/
  project.yml        # XcodeGen spec; the .xcodeproj is generated, not committed
  devenv.nix         # Rust with the iOS targets, XcodeGen
  MarskalKit/        # local Swift package: store, sync, intents, shared views
  Marskal/           # the app target
  MarskalWidget/     # the widget extension
```

- **`sync/ffi`** is its own crate, with its own `devenv.nix`, that depends
  on `sync/core` by path. It holds `Store` behind a mutex, copies reads into
  owned records, and passes timestamps as Unix milliseconds and ids as
  strings. `sync/core` keeps its Rust API and gains no UniFFI attributes.
- One script builds a static library for `aarch64-apple-ios` and
  `aarch64-apple-ios-sim`, wraps both in `MarskalCore.xcframework`, and
  generates the Swift bindings into `MarskalKit`. Both outputs are build
  products, not committed. No Intel simulator.
- **XcodeGen** writes the project from `project.yml`. Xcode itself, and
  `xcodebuild`, come from the host. Everything else comes from devenv.

### Sign-in

- A public Hydra client, **`marskal-ios`**, in `priv/hydra/clients`: the
  authorization code and refresh grants, **PKCE with S256** required, the
  redirect URI above, scopes `offline_access sync:read sync:write`.
- The first screen asks for the server's address. The app reads the
  metadata at `/.well-known/oauth-authorization-server` (ADR 0021), and opens
  the authorization URL in an `ASWebAuthenticationSession`. The web app's own
  login and consent pages run in that sheet; the consent page asks for the
  device's name, as for the device grant.
- The redirect URI is a private-use scheme named after the bundle id
  (RFC 8252), not a universal link. It works against any server without that
  server serving an `apple-app-site-association` file.
- The refresh token and the access token live in the **Keychain**, readable
  only by the app, after first unlock. The widget never reaches the server,
  so it needs no token.
- One Swift actor owns the tokens. It refreshes one at a time, so the
  rotating refresh token is never sent twice.

### The database

- One SQLite file in the App Group container, per server and account, in
  WAL mode. The app and the widget each open it through `sync/ffi`.
- The app **closes its store** when its scene leaves the foreground, and
  runs any write that is under way inside a background task, so a suspended
  app holds no lock. The widget opens the store for each timeline and each
  intent, and closes it after.
- The app reads `data_version` when it returns to the foreground, and
  reloads if the widget wrote. After its own writes it asks WidgetKit to
  reload timelines.

### Sync

- Push, then pull, as ADR 0019 describes. One sync at a time, in one actor.
- When: on launch and on return to the foreground, a moment after a local
  command, on pull to refresh, and in a `BGAppRefreshTask`. The system
  decides how often the last one runs.
- A widget check-off writes the outbox and does not push. The next sync from
  the app sends it.
- Push notifications are later work. They need APNs on the server.

### Intents and the widget

- App Intents live in `MarskalKit`, so the app and the widget share them.
  An interactive widget's button runs the intent in the widget's process;
  Shortcuts and Siri run it in the app's process, without opening the app.
- The intents ADR 0014 lists: add to Inbox, add to a project, complete,
  drop, and read a project's open tasks.

### Text and dates

- Text the user reads is in a **String Catalog** (`Localizable.xcstrings`),
  English as the source language. Whole sentences with interpolated values,
  plurals as the catalog's plural variations, never assembled from pieces.
  This is ADR 0028's rule with Apple's tooling; the iOS app does not read
  the web app's `.po` files.
- User data and API codes are not translated, as on the web.
- Dates are formatted with Foundation's format styles in the user's
  `locale` preference (ADR 0023, 0027), falling back to the device's locale,
  so a date reads the same on the phone as on the web.

### Alternatives considered

- **The device grant**, as the terminal uses. Rejected for the phone: the
  code and the browser are on one screen, and the system sign-in sheet
  needs no code at all.
- **A universal link as the redirect.** Rejected for now. It needs the
  association file on every server the app signs in to. A private-use
  scheme is what RFC 8252 recommends for this case.
- **UniFFI attributes on `sync/core` itself.** Rejected. The terminal client
  uses the borrowed, typed API in-process, and the attributes would bend it
  toward what Swift can take.
- **An App Intents extension.** Rejected. The intents can run in the app's
  process in the background, and an extension is one more target holding the
  database open.
- **A hand-kept `.xcodeproj`, or Tuist.** Rejected. The project is not edited
  in Xcode, and XcodeGen's one YAML file is enough for three targets.
- **iOS 26.** Rejected. It would add availability checks for the one person
  who runs the app, on a phone that already has 27.

## Consequences

- One more Hydra client file, and the first with the authorization code
  grant. The web app's login endpoint already sends a signed-out user to the
  login page and back, and the consent page does not depend on the grant.
- The bundled SQLite in `rusqlite` compiles for iOS with Xcode's clang, not
  Nix's wrapper. The build script sets the compiler for the iOS targets.
- An `.xcframework` and generated bindings must be built before Xcode opens
  the project or `xcodebuild` runs. The build script is the one way to do
  it.
- A device build needs an Apple developer team. Simulator builds do not.
  TestFlight and the App Store are later work, with their own build numbers
  (ADR 0018).
- Tests: `sync/ffi` round-trips in Rust; the Swift shell's sign-in, token
  refresh, and sync loop with Swift Testing, run by `xcodebuild test` on the
  simulator.
