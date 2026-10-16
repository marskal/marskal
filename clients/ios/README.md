# Marskal for iOS

The iOS app (ADR 0029). It links the sync engine, `sync/core`, through the
UniFFI wrapper in `sync/ffi`.

Xcode comes from the host. Everything else comes from this directory's
devenv shell: Rust with the iOS targets, and XcodeGen.

## Build the engine

```sh
devenv shell -- scripts/build-core          # or: scripts/build-core debug
```

This writes `MarskalKit/Frameworks/MarskalCoreFFI.xcframework` and the Swift
bindings, `MarskalKit/Sources/MarskalCore/MarskalCore.swift`. Neither is
committed. Run it again after any change to `sync/core` or `sync/ffi`.

## Build and run the app

```sh
devenv shell -- scripts/build-app
```

This generates `Marskal.xcodeproj` from `project.yml` with XcodeGen, builds
the app for the simulator, and adds new strings to
`Marskal/Localizable.xcstrings` (commit that file). Install and launch it:

```sh
xcrun simctl boot "iPhone 17"
open /Applications/Xcode.app/Contents/Developer/Applications/Simulator.app
xcrun simctl install booted build/derived/Build/Products/Debug-iphonesimulator/Marskal.app
xcrun simctl launch booted app.marskal.ios
```

A debug build offers the dev server, `http://marskal.localhost:8275`
(`devenv up` in `web/`), on its sign-in screen.

## Translations

Text lives in String Catalogs: `Marskal/Localizable.xcstrings`,
`MarskalWidget/Localizable.xcstrings`, and the Siri phrases in
`Marskal/AppShortcuts.xcstrings`. `scripts/build-app` adds new source
strings to them; a translation is a `da` entry beside each key. The app
declares its languages in `project.yml` (`CFBundleLocalizations`). A Siri
phrase must keep `${applicationName}`.

## Install on a phone

Connect the phone, unlock it, and trust this Mac. Developer Mode must be on
(Settings → Privacy & Security, shown once the phone has been connected to
Xcode).

A phone build is signed by your Apple team, which stays out of the
repository. Put its ID in `devenv.local.nix` here, which devenv reads and
git ignores:

```nix
{ env.MARSKAL_DEVELOPMENT_TEAM = "ABCDE12345"; }
```

Xcode does not show the ID of a free account's Personal Team. Create an
Apple Development certificate (Xcode → Settings → Apple Accounts → your
team → Manage Certificates → +), then read the ID from it:

```sh
security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject
```

It is the `OU`. Then:

```sh
devenv shell -- scripts/install-phone
```

With a free account the install stops opening after seven days: run it
again. The first time, trust the developer profile on the phone under
Settings → General → VPN & Device Management. Sign in to a deployed server;
the dev server at `marskal.localhost` is reachable only from this Mac.

## Test

The tests run on an Apple silicon simulator. Install the iOS runtime once,
with `xcodebuild -downloadPlatform iOS`, then:

```sh
cd MarskalKit
xcodebuild test -scheme MarskalKit -destination 'platform=iOS Simulator,name=iPhone 17' ARCHS=arm64
```
