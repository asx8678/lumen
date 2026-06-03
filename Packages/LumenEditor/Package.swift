// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LumenEditor",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "LumenEditor", targets: ["LumenEditor"])
    ],
    dependencies: [
        // Design tokens / theming engine (highlighter colors come from tokens).
        .package(path: "../LumenDesignSystem"),
        // Renderable Markdown model (MarkdownBlock/Inline) for the reading view.
        .package(path: "../LumenCore"),
        // Shared synthetic-data generators / benchmark helpers (test-only use).
        .package(path: "../LumenBenchmark"),
        // tree-sitter Swift binding — incremental parse trees (P2.0.1).
        .package(url: "https://github.com/tree-sitter/swift-tree-sitter", exact: "0.9.0"),
        // Markdown grammar (block + inline C grammars). No release tags exist,
        // so pinned by revision for reproducible builds. This revision is
        // generated with tree-sitter ABI 14, matching swift-tree-sitter 0.9.0's
        // bundled runtime (ABI 14); newer HEAD is ABI 15 and fails to load.
        .package(
            url: "https://github.com/tree-sitter-grammars/tree-sitter-markdown",
            revision: "413285231ce8fa8b11e7074bbe265b48aa7277f9"
        ),
    ],
    targets: [
        .target(
            name: "LumenEditor",
            dependencies: [
                .product(name: "LumenDesignSystem", package: "LumenDesignSystem"),
                .product(name: "LumenCore", package: "LumenCore"),
                .product(name: "SwiftTreeSitter", package: "swift-tree-sitter"),
                .product(name: "TreeSitterMarkdown", package: "tree-sitter-markdown"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "LumenEditorTests",
            dependencies: [
                "LumenEditor",
                .product(name: "LumenBenchmark", package: "LumenBenchmark"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
    ]
)
