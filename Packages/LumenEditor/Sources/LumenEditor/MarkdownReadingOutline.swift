//
//  MarkdownReadingOutline.swift
//  LumenEditor
//
//  A pure, deterministic structural description of a `[MarkdownBlock]` tree —
//  the same lowering the reading view (P2.1.1) renders, expressed as compact
//  tags. It exists so the block→render mapping can be unit-tested without
//  standing up SwiftUI: each tag names the view the reading view will produce.
//

import Foundation
import LumenCore

/// Produces compact structural tags for a renderable Markdown tree.
public enum MarkdownReadingOutline {
    /// Flattens `blocks` into ordered structural tags (e.g. `h1`, `p`,
    /// `code(swift)`, `ul`, `task[checked]`, `table(2x1)`, `link`).
    public static func describe(_ blocks: [MarkdownBlock]) -> [String] {
        blocks.flatMap(describe(_:))
    }

    private static func describe(_ block: MarkdownBlock) -> [String] {
        switch block {
        case .heading(let level, let inlines):
            return ["h\(level)"] + inlineTags(inlines)
        case .paragraph(let inlines):
            if case .image(let source, _)? = soleImage(inlines) {
                return ["image(\(source ?? ""))"]
            }
            return ["p"] + inlineTags(inlines)
        case .codeBlock(let language, _):
            return ["code(\(language ?? "plain"))"]
        case .blockQuote(let children):
            return ["quote"] + describe(children)
        case .unorderedList(let items):
            return ["ul"] + items.flatMap(describe(item:))
        case .orderedList(let start, let items):
            return ["ol(\(start))"] + items.flatMap(describe(item:))
        case .thematicBreak:
            return ["hr"]
        case .table(let table):
            return ["table(\(table.header.count)x\(table.rows.count))"]
        case .htmlBlock:
            return ["html"]
        }
    }

    private static func describe(item: MarkdownListItem) -> [String] {
        let marker: String
        switch item.checkbox {
        case .checked: marker = "task[checked]"
        case .unchecked: marker = "task[unchecked]"
        case nil: marker = "li"
        }
        return [marker] + describe(item.children)
    }

    /// Inline-level tags worth surfacing in the structure (currently links).
    private static func inlineTags(_ inlines: [MarkdownInline]) -> [String] {
        var tags: [String] = []
        for inline in inlines {
            switch inline {
            case .link: tags.append("link")
            case .emphasis(let c), .strong(let c), .strikethrough(let c):
                tags.append(contentsOf: inlineTags(c))
            default: break
            }
        }
        return tags
    }

    /// Returns the single image inline if `inlines` is effectively just an
    /// image (the standalone-image-paragraph case), else `nil`.
    private static func soleImage(_ inlines: [MarkdownInline]) -> MarkdownInline? {
        let meaningful = inlines.filter { inline in
            if case .text(let s) = inline, s.trimmingCharacters(in: .whitespaces).isEmpty {
                return false
            }
            if case .softBreak = inline { return false }
            return true
        }
        if meaningful.count == 1, case .image = meaningful[0] {
            return meaningful[0]
        }
        return nil
    }
}
