//
//  MarkdownDocumentParser.swift
//  LumenCore
//
//  Parses a note's Markdown *body* into a full-document AST via Apple's
//  swift-markdown (cmark-gfm), and converts that AST into a `Sendable`,
//  walkable intermediate block model (``MarkdownBlock`` / ``MarkdownInline``).
//
//  This is COMPLEMENTARY to the editor's tree-sitter parser:
//    • tree-sitter  → fast, incremental decoration of the live editor buffer.
//    • swift-markdown → a clean, full-document AST for rendering (reading view,
//      P2.1.x) and future export/Publish.
//
//  Frontmatter is handled separately by ``FrontmatterParser``; this parser
//  always operates on the stripped body so `---` YAML fences never pollute the
//  document tree.
//

import Foundation
import Markdown

/// Builds full-document Markdown ASTs and a renderable intermediate model.
///
/// Pure utility — no storage, no UI. The intermediate ``MarkdownBlock`` tree is
/// what the reading view (P2.1.1) consumes to render blocks; it is deliberately
/// decoupled from swift-markdown's reference types so the UI layer stays
/// `Sendable`-clean and free of a direct cmark dependency.
public enum MarkdownDocumentParser {
    /// Parses `text` into a swift-markdown `Document`, stripping any leading
    /// YAML frontmatter block first (so the AST reflects the body only).
    ///
    /// - Parameter text: The note's full Markdown source (frontmatter allowed).
    /// - Returns: The parsed `Document` for the note body.
    public static func parseDocument(_ text: String) -> Document {
        let body = FrontmatterParser.parse(text).body
        return Document(parsing: body, options: [.parseBlockDirectives])
    }

    /// Parses `text` and lowers it into the renderable ``MarkdownBlock`` tree.
    ///
    /// - Parameter text: The note's full Markdown source (frontmatter allowed).
    /// - Returns: The top-level blocks of the note body.
    public static func parseBlocks(_ text: String) -> [MarkdownBlock] {
        let document = parseDocument(text)
        return MarkdownBlockBuilder.blocks(from: document)
    }
}
