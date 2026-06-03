// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LumenGraph",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "LumenGraph", targets: ["LumenGraph"])
    ],
    targets: [
        .target(
            name: "LumenGraph",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
