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

## Test

The tests run on an Apple silicon simulator. Install the iOS runtime once,
with `xcodebuild -downloadPlatform iOS`, then:

```sh
cd MarskalKit
xcodebuild test -scheme MarskalKit -destination 'platform=iOS Simulator,name=iPhone 17' ARCHS=arm64
```
