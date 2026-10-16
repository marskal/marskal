// swift-tools-version: 6.2

// What the app and the widget share (ADR 0029). MarskalCore is the engine,
// sync/ffi built by scripts/build-core; run that before building this.
import PackageDescription

let package = Package(
    name: "MarskalKit",
    platforms: [.iOS("27.0")],
    products: [
        .library(name: "MarskalCore", targets: ["MarskalCore"]),
    ],
    targets: [
        .binaryTarget(name: "MarskalCoreFFI", path: "Frameworks/MarskalCoreFFI.xcframework"),
        .target(name: "MarskalCore", dependencies: ["MarskalCoreFFI"]),
        .testTarget(name: "MarskalCoreTests", dependencies: ["MarskalCore"]),
    ]
)
