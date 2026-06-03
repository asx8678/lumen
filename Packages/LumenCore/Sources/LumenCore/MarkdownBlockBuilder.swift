//
//  MarkdownBlockBuilder.swift
//  LumenCore
//
//  Lowers a swift-markdown `Document` into the `Sendable` ``MarkdownBlock``
//  intermediate tree consumed by the reading view (P2.1.1) and export.
//
//  Implemented as recursive converters over swift-markdown's `Markup` types.
//  This is the visitor scaffold for the AST → renderable-model lowering; the
//  reading-view UI is deliberately NOT built here (that is P2.1.1).
//

import Foundation
import Markdown

/// Converts swift-markdown `Markup` nodes into the renderable intermediate model.
enum MarkdownBlockBuilder {
    /// Lowers all top-level children of `document` into ``MarkdownBlock`` nodes.
    static func blocks(from document: Document) -> [MarkdownBlock] {
        document.blockChildren.compactMap(block(from:))
    }

    // MARK: - Block lowering

    private static func blocks(from container: some Markup) -> [MarkdownBlock] {
        container.children.compactMap { child in
            (child as? BlockMarkup).flatMap(block(from:))
        }
    }

    private static func block(from markup: BlockMarkup) -> MarkdownBlock? {
        switch markup {
        case let heading as Heading:
            return .heading(level: heading.level, inlines(of: heading))
        case let paragraph as Paragraph:
            return .paragraph(inlines(of: paragraph))
        case let codeBlock as CodeBlock:
            let language = codeBlock.language?.trimmingCharacters(in: .whitespaces)
            return .codeBlock(
                language: (language?.isEmpty == true) ? nil : language,
                code: codeBlock.code)
        case let quote as BlockQuote:
            return .blockQuote(blocks(from: quote))
        case let list as UnorderedList:
            return .unorderedList(list.listItems.map(listItem(from:)))
        case let list as OrderedList:
            return .orderedList(
                start: Int(list.startIndex),
                items: list.listItems.map(listItem(from:)))
        case is ThematicBreak:
            return .thematicBreak
        case let table as Table:
            return .table(self.table(from: table))
        case let html as HTMLBlock:
            return .htmlBlock(html.rawHTML)
        default:
            return nil
        }
    }

    private static func listItem(from item: ListItem) -> MarkdownListItem {
        let checkbox: MarkdownCheckbox? =
            switch item.checkbox {
            case .checked: .checked
            case .unchecked: .unchecked
            case nil: nil
            }
        return MarkdownListItem(checkbox: checkbox, children: blocks(from: item))
    }

    private static func table(from table: Table) -> MarkdownTable {
        let alignments = table.columnAlignments.map { alignment -> MarkdownColumnAlignment? in
            switch alignment {
            case .left: .left
            case .center: .center
            case .right: .right
            case nil: nil
            }
        }
        let header = table.head.cells.map { inlines(of: $0) }
        let rows = table.body.rows.map { row in
            row.cells.map { inlines(of: $0) }
        }
        return MarkdownTable(
            columnAlignments: alignments,
            header: Array(header),
            rows: rows.map(Array.init))
    }

    // MARK: - Inline lowering

    private static func inlines(of container: some Markup) -> [MarkdownInline] {
        container.children.compactMap { child in
            (child as? InlineMarkup).flatMap(inline(from:))
        }
    }

    private static func inline(from markup: InlineMarkup) -> MarkdownInline? {
        switch markup {
        case let text as Text:
            return .text(text.string)
        case let emphasis as Emphasis:
            return .emphasis(inlines(of: emphasis))
        case let strong as Strong:
            return .strong(inlines(of: strong))
        case let strikethrough as Strikethrough:
            return .strikethrough(inlines(of: strikethrough))
        case let code as InlineCode:
            return .inlineCode(code.code)
        case let link as Link:
            return .link(destination: link.destination, inlines(of: link))
        case let image as Image:
            return .image(source: image.source, alt: image.plainText)
        case is LineBreak:
            return .lineBreak
        case is SoftBreak:
            return .softBreak
        case let html as InlineHTML:
            return .inlineHTML(html.rawHTML)
        default:
            return nil
        }
    }
}
