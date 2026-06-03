// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LumenCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "LumenCore", targets: ["LumenCore"])
    ],
    dependencies: [
        // YAML frontmatter parsing (P1.7).
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0")
    ],
    targets: [
        .target(
            name: "LumenCore",
            dependencies: [
                .product(name: "Yams", package: "Yams")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "LumenCoreTests",
            dependencies: ["LumenCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
    ]
)
