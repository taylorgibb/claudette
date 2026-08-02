// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Claudette",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Claudette", targets: ["Claudette"]),
        .library(name: "ClaudetteCore", targets: ["ClaudetteCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/PostHog/posthog-ios.git", from: "3.0.0"),
    ],
    targets: [
        .target(
            name: "ClaudetteCore",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "Claudette",
            dependencies: [
                "ClaudetteCore",
                .product(name: "PostHog", package: "posthog-ios"),
            ]
        ),
        .testTarget(
            name: "ClaudetteCoreTests",
            dependencies: ["ClaudetteCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
