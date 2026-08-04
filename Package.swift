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
    dependencies: [],
    targets: [
        .target(
            name: "ClaudetteCore",
            resources: [.process("Resources")]
        ),
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
