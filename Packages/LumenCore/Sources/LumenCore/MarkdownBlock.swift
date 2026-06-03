//
//  MarkdownBlock.swift
//  LumenCore
//
//  A `Sendable`, value-type intermediate model lowered from a swift-markdown
//  `Document` (see ``MarkdownDocumentParser``). The reading view (P2.1.1)
//  renders this tree directly; keeping it free of swift-markdown's reference
//  types means the UI layer stays `Sendable`-clean and decoupled from cmark.
//

import Foundation

/// A block-level node in the renderable Markdown tree.
public indirect enum MarkdownBlock: Sendable, Equatable {
    /// An ATX/Setext heading. `level` is 1...6.
    case heading(level: Int, [MarkdownInline])
    /// A paragraph of inline content.
    case paragraph([MarkdownInline])
    /// A fenced or indented code block. `language` is the info-string language.
    case codeBlock(language: String?, code: String)
    /// A block quote containing nested blocks.
    case blockQuote([MarkdownBlock])
    /// An unordered (bulleted) list.
    case unorderedList([MarkdownListItem])
    /// An ordered (numbered) list. `start` is the first item's number.
    case orderedList(start: Int, items: [MarkdownListItem])
    /// A `---`/`***`/`___` thematic break (horizontal rule).
    case thematicBreak
    /// A GFM table.
    case table(MarkdownTable)
    /// A raw HTML block, preserved verbatim.
    case htmlBlock(String)
}

/// A single list item, with optional GFM task-list checkbox state.
public struct MarkdownListItem: Sendable, Equatable {
    /// `nil` for a plain bullet; otherwise the task-list checkbox state.
    public var checkbox: MarkdownCheckbox?
    /// The item's block-level children.
    public var children: [MarkdownBlock]

    public init(checkbox: MarkdownCheckbox? = nil, children: [MarkdownBlock]) {
        self.checkbox = checkbox
        self.children = children
    }
}

/// The state of a GFM task-list checkbox.
public enum MarkdownCheckbox: Sendable, Equatable {
    case unchecked
    case checked
}

/// A GFM table: column alignments, a header row, and zero or more body rows.
public struct MarkdownTable: Sendable, Equatable {
    /// Per-column alignment; `nil` means unspecified/default.
    public var columnAlignments: [MarkdownColumnAlignment?]
    /// The header cells (each cell is inline content).
    public var header: [[MarkdownInline]]
    /// The body rows (each row is an array of inline-content cells).
    public var rows: [[[MarkdownInline]]]

    public init(
        columnAlignments: [MarkdownColumnAlignment?],
        header: [[MarkdownInline]],
        rows: [[[MarkdownInline]]]
    ) {
        self.columnAlignments = columnAlignments
        self.header = header
        self.rows = rows
    }
}

/// A GFM table column alignment.
public enum MarkdownColumnAlignment: Sendable, Equatable {
    case left
    case center
    case right
}

/// An inline-level node in the renderable Markdown tree.
public indirect enum MarkdownInline: Sendable, Equatable {
    /// Literal text.
    case text(String)
    /// `*emphasis*` / `_emphasis_`.
    case emphasis([MarkdownInline])
    /// `**strong**` / `__strong__`.
    case strong([MarkdownInline])
    /// `~~strikethrough~~` (GFM).
    case strikethrough([MarkdownInline])
    /// `` `inline code` ``.
    case inlineCode(String)
    /// A link with an optional destination and inline children.
    case link(destination: String?, [MarkdownInline])
    /// An image with an optional source and plain-text alternate text.
    case image(source: String?, alt: String)
    /// A hard line break (`\` or two trailing spaces).
    case lineBreak
    /// A soft line break (a plain newline within a paragraph).
    case softBreak
    /// Raw inline HTML, preserved verbatim.
    case inlineHTML(String)
}
