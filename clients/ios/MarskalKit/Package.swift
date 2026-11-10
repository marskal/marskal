// swift-tools-version: 6.2

// What the app and the widget share (ADR 0029). MarskalCore is the engine,
// core/ffi built by scripts/build-core; run that before building this.
// MarskalKit is the shell around it: sign-in, tokens, and sync.
import PackageDescription

let package = Package(
    name: "MarskalKit",
    platforms: [.iOS("27.0")],
    products: [
        .library(name: "MarskalKit", targets: ["MarskalKit"]),
    ],
    targets: [
        .binaryTarget(name: "MarskalCoreFFI", path: "Frameworks/MarskalCoreFFI.xcframework"),
        .target(name: "MarskalCore", dependencies: ["MarskalCoreFFI"]),
        .target(name: "MarskalKit", dependencies: ["MarskalCore"]),
        .testTarget(name: "MarskalCoreTests", dependencies: ["MarskalCore"]),
        .testTarget(name: "MarskalKitTests", dependencies: ["MarskalKit"]),
    ]
)
