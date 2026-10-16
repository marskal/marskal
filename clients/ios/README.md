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

## Test

The tests run on an Apple silicon simulator. Install the iOS runtime once,
with `xcodebuild -downloadPlatform iOS`, then:

```sh
cd MarskalKit
xcodebuild test -scheme MarskalKit -destination 'platform=iOS Simulator,name=iPhone 17' ARCHS=arm64
```
