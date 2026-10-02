// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MeasureMeKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "MeasureMeCore", targets: ["MeasureMeCore"])
    ],
    targets: [
        // Platform-independent logic: units, measurement model, validation,
        // size charts, recommendation, silhouette geometry and capture-quality rules.
        // Depends on Foundation only so it can be unit-tested anywhere (`swift test`).
        .target(
            name: "MeasureMeCore",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "MeasureMeCoreTests",
            dependencies: ["MeasureMeCore"]
        )
    ]
)
