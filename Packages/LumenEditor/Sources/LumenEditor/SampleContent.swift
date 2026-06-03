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

    // Note: the large synthetic-document generator was promoted to
    // `LumenBenchmark.SyntheticData.markdownDocument(lineCount:)` (P1.3) so the
    // benchmark harness and tests share one implementation.
}
