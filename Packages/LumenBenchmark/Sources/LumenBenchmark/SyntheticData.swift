//
//  SyntheticData.swift
//  LumenBenchmark
//
//  Reusable synthetic-data generators for performance benchmarks and tests.
//  Centralizes the ad-hoc generators that grew out of the P1.10 / P1.12 spikes.
//
//  P1.3 scope: the harness skeleton only. The real large-vault benchmark that
//  consumes these generators is P1.22.
//

import Foundation

/// Generators for synthetic Markdown content and vaults.
public enum SyntheticData {

    // MARK: - Documents

    /// Generates a large synthetic Markdown document.
    ///
    /// Mixes headings, paragraphs, list items, code, and blockquotes so layout
    /// and highlighting exercise varied element types rather than uniform lines.
    ///
    /// - Parameter lineCount: Approximate number of lines to generate.
    /// - Returns: A Markdown string with roughly `lineCount` lines.
    public static func markdownDocument(lineCount: Int) -> String {
        var lines: [String] = []
        lines.reserveCapacity(lineCount)
        for i in 0..<lineCount {
            switch i % 8 {
            case 0:
                lines.append("# Section \(i / 8)")
            case 1:
                lines.append("")
            case 2:
                lines.append(
                    "This is paragraph line \(i) with some **bold** and *italic* text to vary layout."
                )
            case 3:
                lines.append("- list item \(i): the quick brown fox jumps over the lazy dog")
            case 4:
                lines.append("    let value\(i) = compute(\(i))  // inline code-ish content")
            case 5:
                lines.append("> A blockquote on line \(i) to exercise a different paragraph style.")
            case 6:
                lines.append(
                    "Another paragraph \(i) — lorem ipsum dolor sit amet, consectetur adipiscing."
                )
            default:
                lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Vaults

    /// A synthetic vault written to a temporary directory.
    ///
    /// The caller owns the directory and should call ``cleanup()`` (or remove
    /// `root`) when finished.
    public struct SyntheticVault: Sendable {
        /// The vault's root directory.
        public let root: URL
        /// Paths of the generated `.md` files.
        public let files: [URL]

        /// Removes the vault directory tree from disk. Best-effort.
        public func cleanup() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    /// Creates a synthetic vault: a temp directory tree of `fileCount` `.md`
    /// files of varying sizes, spread across a few subfolders.
    ///
    /// - Parameters:
    ///   - fileCount: Number of Markdown files to generate.
    ///   - subfolders: Number of subfolders to distribute files across.
    ///   - maxLinesPerFile: Upper bound on lines per file (sizes vary 1…max).
    /// - Returns: A ``SyntheticVault`` describing the written tree.
    /// - Throws: Any filesystem error from creating directories or files.
    public static func makeVault(
        fileCount: Int,
        subfolders: Int = 4,
        maxLinesPerFile: Int = 200
    ) throws -> SyntheticVault {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LumenSyntheticVault-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)

        let folderCount = max(1, subfolders)
        for f in 0..<folderCount {
            try fm.createDirectory(
                at: root.appendingPathComponent("folder-\(f)"),
                withIntermediateDirectories: true
            )
        }

        var files: [URL] = []
        files.reserveCapacity(fileCount)
        for i in 0..<fileCount {
            let folder = root.appendingPathComponent("folder-\(i % folderCount)")
            let fileURL = folder.appendingPathComponent("note-\(i).md")
            // Deterministic but varied size: 1…maxLinesPerFile lines.
            let lines = (i % maxLinesPerFile) + 1
            let body = markdownDocument(lineCount: lines)
            try body.write(to: fileURL, atomically: true, encoding: .utf8)
            files.append(fileURL)
        }
        return SyntheticVault(root: root, files: files)
    }
}
