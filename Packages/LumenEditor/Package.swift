// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LumenEditor",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "LumenEditor", targets: ["LumenEditor"])
    ],
    dependencies: [
        // Design tokens / theming engine (highlighter colors come from tokens).
        .package(path: "../LumenDesignSystem"),
        // Shared synthetic-data generators / benchmark helpers (test-only use).
        .package(path: "../LumenBenchmark"),
    ],
    targets: [
        .target(
            name: "LumenEditor",
            dependencies: [
                .product(name: "LumenDesignSystem", package: "LumenDesignSystem")
            ],
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
