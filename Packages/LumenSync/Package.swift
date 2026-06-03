// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LumenSync",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "LumenSync", targets: ["LumenSync"])
    ],
    targets: [
        .target(
            name: "LumenSync",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
