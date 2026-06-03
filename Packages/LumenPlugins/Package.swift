// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LumenPlugins",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "LumenPlugins", targets: ["LumenPlugins"])
    ],
    targets: [
        .target(
            name: "LumenPlugins",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
