// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LumenEditor",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "LumenEditor", targets: ["LumenEditor"])
    ],
    dependencies: [
        // Shared synthetic-data generators / benchmark helpers (test-only use).
        .package(path: "../LumenBenchmark")
    ],
    targets: [
        .target(
            name: "LumenEditor",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "LumenEditorTests",
            dependencies: [
                "LumenEditor",
                .product(name: "LumenBenchmark", package: "LumenBenchmark"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
    ]
)
