//
//  MarkdownTreeSitterParser.swift
//  LumenEditor
//
//  P2.0.1 — Parsing backbone for Phase 2 (rich editing).
//
//  Wraps the tree-sitter Markdown grammars (block + inline) behind an actor so
//  parsing runs OFF the keystroke hot path. Maintains a persistent block parse
//  tree and reparses *incrementally* when the document changes (tree-sitter
//  `edit` + reparse with the old tree), rather than re-parsing from scratch.
//
//  This file intentionally does NOT change the user-visible highlighting
//  output — it only makes the parse tree + a viewport-scoped query API
//  available for the next tasks (lumen-nmm.2 migrates the highlighter onto it).
//
//  Byte offsets: SwiftTreeSitter parses with `TSInputEncodingUTF16`, so a
//  tree-sitter "byte" is one UTF-16 byte. A UTF-16 code-unit index `u` (the
//  unit used by `NSString`/`NSRange`) therefore maps to byte `u * 2`.
//

import Foundation
import SwiftTreeSitter
import TreeSitterMarkdown
import TreeSitterMarkdownInline

/// A node from the Markdown parse tree, scoped to document coordinates.
///
/// All ranges are expressed in UTF-16 code units (matching `NSString` /
/// `NSTextView`), so callers can apply them to `NSTextStorage` directly.
public struct MarkdownSyntaxNode: Sendable, Hashable {
    /// The tree-sitter node type (e.g. `atx_heading`, `emphasis`, `code_span`).
    public let type: String
    /// The node's character range in UTF-16 code units within the document.
    public let range: NSRange
    /// `true` if the node came from the inline grammar (emphasis, links, …),
    /// `false` for block-level structure (headings, lists, fenced code, …).
    public let isInline: Bool

    public init(type: String, range: NSRange, isInline: Bool) {
        self.type = type
        self.range = range
        self.isInline = isInline
    }
}

/// Describes a text edit in UTF-16 code-unit coordinates, mirroring the
/// information `NSTextStorage` reports (`editedRange` + `changeInLength`).
public struct MarkdownTextEdit: Sendable, Hashable {
    /// The edited range *in the new text* (post-edit), in UTF-16 code units.
    public let editedRange: NSRange
    /// The change in length (new length − old length) for the edited region.
    public let changeInLength: Int

    public init(editedRange: NSRange, changeInLength: Int) {
        self.editedRange = editedRange
        self.changeInLength = changeInLength
    }
}

/// Incremental Markdown parser backed by tree-sitter's block + inline grammars.
///
/// The actor confines all tree-sitter state (parsers, the mutable block tree,
/// the source snapshot) to a single isolation domain, so it is safe to drive
/// from the editor's `@MainActor` coordinator via `Task { await … }` without
/// blocking typing. Query results are `Sendable` value types; raw `Node`s never
/// escape the actor.
public actor MarkdownTreeSitterParser {
    private let blockParser = Parser()
    private let inlineParser = Parser()

    /// The persistent block parse tree, kept across edits for incremental
    /// reparsing. `nil` until the first `parse(_:)`.
    private var blockTree: MutableTree?

    /// The current source snapshot (used to extract inline substrings and to
    /// compute pre-edit points for `InputEdit`).
    private var source: String = ""

    /// Creates a parser with both Markdown grammars installed.
    ///
    /// - Throws: `ParserError` if either grammar fails to load (a programmer /
    ///   packaging error rather than a runtime condition).
    public init() throws {
        try blockParser.setLanguage(Language(language: tree_sitter_markdown()))
        try inlineParser.setLanguage(Language(language: tree_sitter_markdown_inline()))
    }

    // MARK: - Parsing

    /// Parses `text` from scratch, replacing any existing tree.
    public func parse(_ text: String) {
        source = text
        blockTree = blockParser.parse(text)
    }

    /// Applies an incremental edit and reparses using the retained tree.
    ///
    /// Falls back to a full parse if there is no existing tree (first edit).
    /// - Parameters:
    ///   - edit: The edit in UTF-16 code-unit coordinates.
    ///   - newText: The full document text *after* the edit.
    public func applyEdit(_ edit: MarkdownTextEdit, newText: String) {
        guard let tree = blockTree else {
            parse(newText)
            return
        }

        let oldText = source
        let startUTF16 = edit.editedRange.location
        let newEndUTF16 = edit.editedRange.location + edit.editedRange.length
        let oldEndUTF16 = newEndUTF16 - edit.changeInLength

        let inputEdit = InputEdit(
            startByte: startUTF16 * 2,
            oldEndByte: oldEndUTF16 * 2,
            newEndByte: newEndUTF16 * 2,
            startPoint: Self.point(in: oldText, atUTF16: startUTF16),
            oldEndPoint: Self.point(in: oldText, atUTF16: oldEndUTF16),
            newEndPoint: Self.point(in: newText, atUTF16: newEndUTF16))

        tree.edit(inputEdit)
        source = newText
        blockTree = blockParser.parse(tree: tree, string: newText)
    }

    // MARK: - Query API (viewport-scoped friendly)

    /// Returns the parse-tree nodes overlapping `range`, including inline nodes
    /// (emphasis, links, code spans) discovered by reparsing the block grammar's
    /// `inline` leaves with the inline grammar.
    ///
    /// Intended to be called with the visible viewport range so the inline
    /// reparse cost stays bounded, mirroring the Phase 1 viewport highlighter.
    /// - Parameter range: A UTF-16 code-unit range in the document.
    /// - Returns: Named nodes whose ranges intersect `range`, in document order.
    public func nodes(in range: NSRange) -> [MarkdownSyntaxNode] {
        guard blockTree?.rootNode != nil else { return [] }
        let queryByteRange = byteRange(for: range)

        var out: [MarkdownSyntaxNode] = []
        let ns = source as NSString
        var inlineRegions: [NSRange] = []
        blockTree?.enumerateNodes(in: queryByteRange) { node in
            guard node.isNamed, let type = node.nodeType else { return }
            let nsRange = node.range
            out.append(MarkdownSyntaxNode(type: type, range: nsRange, isInline: false))
            if type == "inline" {
                inlineRegions.append(nsRange)
            }
        }

        for region in inlineRegions {
            let clamped = NSIntersectionRange(region, NSRange(location: 0, length: ns.length))
            guard clamped.length > 0 else { continue }
            let substring = ns.substring(with: clamped)
            guard let inlineTree = inlineParser.parse(substring),
                inlineTree.rootNode != nil
            else { continue }
            let fullInline = NSRange(location: 0, length: (substring as NSString).length)
            inlineTree.enumerateNodes(in: byteRange(for: fullInline)) { node in
                guard node.isNamed, let type = node.nodeType else { return }
                let local = node.range
                let mapped = NSRange(
                    location: clamped.location + local.location,
                    length: local.length)
                out.append(MarkdownSyntaxNode(type: type, range: mapped, isInline: true))
            }
        }

        return out
    }

    /// Returns the root node's S-expression, or `nil` if there is no tree.
    /// Useful for tests and debugging the parse structure.
    public func rootSExpression() -> String? {
        blockTree?.rootNode?.sExpressionString
    }

    // MARK: - Helpers

    /// Converts a UTF-16 code-unit `NSRange` to a tree-sitter byte range.
    private func byteRange(for range: NSRange) -> Range<UInt32> {
        let start = UInt32(range.location) * 2
        let end = UInt32(range.location + range.length) * 2
        return start..<end
    }

    /// Computes the tree-sitter `Point` (row + UTF-16 byte column) for a UTF-16
    /// code-unit offset within `text`.
    private static func point(in text: String, atUTF16 offset: Int) -> Point {
        var row = 0
        var lineStartUTF16 = 0
        var index = 0
        let newline: UInt16 = 0x000A
        for unit in text.utf16 {
            if index >= offset { break }
            if unit == newline {
                row += 1
                lineStartUTF16 = index + 1
            }
            index += 1
        }
        let column = (offset - lineStartUTF16) * 2
        return Point(row: row, column: max(0, column))
    }
}
