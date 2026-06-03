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
    dependencies: [
        // The real indexing pipeline (enumerate/parse/hash/upsert) lives in
        // LumenCore; the large-vault benchmark (P1.22) exercises it directly.
        // LumenCore does NOT depend on LumenBenchmark, so this is acyclic.
        .package(path: "../LumenCore")
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
            dependencies: [
                "LumenBenchmark",
                .product(name: "LumenCore", package: "LumenCore"),
            ],
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
