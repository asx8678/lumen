//
//  SampleContent.swift
//  LumenEditor
//
//  Sample / synthetic Markdown content used to demo the editor host and to
//  drive the P1.10 large-document performance spike.
//

import Foundation

/// Sample Markdown content helpers for the editor.
public enum SampleContent {
    /// A short multi-paragraph Markdown document shown when the app launches,
    /// so the live TextKit 2 editor is visibly working.
    public static let welcomeMarkdown = """
    # Welcome to Lumen

    This is the **TextKit 2** editor host (P1.10). It renders with viewport-based
    layout on `NSTextLayoutManager` / `NSTextContentStorage` — no legacy TextKit 1
    layout manager is involved.

    ## What works here

    - Editing flows through a two-way `Binding<String>`.
    - User edits are bridged back to SwiftUI via the coordinator.
    - Built-in undo is enabled (custom undo wiring is P1.11).

    > Syntax highlighting, autosave, and typography controls land in later
    > Phase-1 tasks. This is *just* the editor host.

    Type below to confirm the binding is live.
    """

    /// Generates a large synthetic Markdown document for performance testing.
    ///
    /// The output mixes headings, paragraphs, list items, and code so the layout
    /// engine exercises varied element types rather than uniform lines.
    ///
    /// - Parameter lineCount: Approximate number of lines to generate.
    /// - Returns: A Markdown string with roughly `lineCount` lines.
    public static func syntheticMarkdown(lineCount: Int) -> String {
        var lines: [String] = []
        lines.reserveCapacity(lineCount)
        for i in 0..<lineCount {
            switch i % 8 {
            case 0:
                lines.append("# Section \(i / 8)")
            case 1:
                lines.append("")
            case 2:
                lines.append("This is paragraph line \(i) with some **bold** and *italic* text to vary layout.")
            case 3:
                lines.append("- list item \(i): the quick brown fox jumps over the lazy dog")
            case 4:
                lines.append("    let value\(i) = compute(\(i)) // inline code-ish content")
            case 5:
                lines.append("> A blockquote on line \(i) to exercise a different paragraph style.")
            case 6:
                lines.append("Another paragraph \(i) — lorem ipsum dolor sit amet, consectetur adipiscing.")
            default:
                lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }
}
