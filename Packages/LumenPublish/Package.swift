// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LumenPublish",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "LumenPublish", targets: ["LumenPublish"])
    ],
    targets: [
        .target(
            name: "LumenPublish",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
