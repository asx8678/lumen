// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LumenBases",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "LumenBases", targets: ["LumenBases"])
    ],
    targets: [
        .target(
            name: "LumenBases",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
