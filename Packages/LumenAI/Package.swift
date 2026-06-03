// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LumenAI",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "LumenAI", targets: ["LumenAI"])
    ],
    targets: [
        .target(
            name: "LumenAI",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
