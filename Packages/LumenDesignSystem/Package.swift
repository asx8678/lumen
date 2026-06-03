// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LumenDesignSystem",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "LumenDesignSystem", targets: ["LumenDesignSystem"])
    ],
    targets: [
        .target(
            name: "LumenDesignSystem",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "LumenDesignSystemTests",
            dependencies: ["LumenDesignSystem"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
    ]
)
