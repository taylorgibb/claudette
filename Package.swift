// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Claudette",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Claudette", targets: ["Claudette"]),
        .library(name: "ClaudetteCore", targets: ["ClaudetteCore"]),
        .library(name: "ClaudetteUI", targets: ["ClaudetteUI"]),
    ],
    // No external dependencies: `swift test` builds and runs from a clean
    // clone with nothing but a Swift toolchain.
    dependencies: [],
    targets: [
        .target(
            name: "ClaudetteCore",
            resources: [.process("Resources")]
        ),
        // AppKit and SwiftUI live here rather than in the executable, so the
        // views, the view model and the formatters all have somewhere to be
        // tested from. `Claudette` itself is only a composition root.
        .target(
            name: "ClaudetteUI",
            dependencies: ["ClaudetteCore"]
        ),
        .executableTarget(
            name: "Claudette",
            dependencies: ["ClaudetteCore", "ClaudetteUI"]
        ),
        .testTarget(
            name: "ClaudetteCoreTests",
            dependencies: ["ClaudetteCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "ClaudetteUITests",
            dependencies: ["ClaudetteUI"]
        ),
    ]
)
