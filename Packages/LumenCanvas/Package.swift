// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LumenCanvas",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "LumenCanvas", targets: ["LumenCanvas"])
    ],
    targets: [
        .target(
            name: "LumenCanvas",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
