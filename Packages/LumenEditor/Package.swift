// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LumenEditor",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "LumenEditor", targets: ["LumenEditor"])
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
            dependencies: ["LumenEditor"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
