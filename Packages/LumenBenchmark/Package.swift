// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LumenBenchmark",
    platforms: [.macOS(.v26)],
    products: [
        // Reusable harness: synthetic data generators + measurement helpers.
        .library(name: "LumenBenchmark", targets: ["LumenBenchmark"]),
        // Command-line runner so CI / Scripts/check.sh can invoke benchmarks.
        .executable(name: "lumen-bench", targets: ["lumen-bench"]),
    ],
    targets: [
        .target(
            name: "LumenBenchmark",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .executableTarget(
            name: "lumen-bench",
            dependencies: ["LumenBenchmark"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "LumenBenchmarkTests",
            dependencies: ["LumenBenchmark"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
    ]
)
