//
//  MarkdownReadingView.swift
//  LumenEditor
//
//  The rendered, read-only reading view (P2.1.1): renders LumenCore's
//  `[MarkdownBlock]` natively with SwiftUI, styled from the design-system
//  tokens so it matches the app's calm dark theme. Blocks render lazily in a
//  `ScrollView`/`LazyVStack` so large notes stay smooth; inline styling comes
//  from `MarkdownInlineRenderer`.
//
//  Scope note: math (`$…$`/`$$…$$`) and Mermaid are later tasks (nmm.6/.7) —
//  here they render as ordinary text / code blocks.
//

import LumenCore
import LumenDesignSystem
import SwiftUI

/// A native, read-only rendering of a parsed Markdown document.
public struct MarkdownReadingView: View {
    private let blocks: [MarkdownBlock]
    private let theme: Theme
    private let baseFontSize: CGFloat
    private let maxContentWidth: CGFloat?
    private let baseURL: URL?

    /// Creates a reading view.
    ///
    /// - Parameters:
    ///   - blocks: The renderable block tree (from `MarkdownDocumentParser`).
    ///   - theme: The resolved design-system theme (colors).
    ///   - baseFontSize: The body text size (the editor's size preference).
    ///   - maxContentWidth: A readable max line width, or `nil` for full width.
    ///   - baseURL: The note's directory, for resolving vault-relative images.
    public init(
        blocks: [MarkdownBlock],
        theme: Theme,
        baseFontSize: CGFloat = 16,
        maxContentWidth: CGFloat? = 680,
        baseURL: URL? = nil
    ) {
        self.blocks = blocks
        self.theme = theme
        self.baseFontSize = baseFontSize
        self.maxContentWidth = maxContentWidth
        self.baseURL = baseURL
    }

    public var body: some View {
        let style = ReadingStyle(theme: theme, baseFontSize: baseFontSize, baseURL: baseURL)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.md) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    MarkdownBlockView(block: block, style: style)
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.lg)
            .frame(maxWidth: maxContentWidth ?? .infinity, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(theme.color(.editorBackground))
        .textSelection(.enabled)
    }
}

// MARK: - Shared styling

/// Resolved styling shared by all block/inline renderers.
struct ReadingStyle {
    let theme: Theme
    let baseFontSize: CGFloat
    let baseURL: URL?

    var bodyFont: Font { .system(size: baseFontSize) }
    var codeFont: Font { .system(size: baseFontSize - 1, design: .monospaced) }

    /// Heading point size for a 1...6 level.
    func headingFont(level: Int) -> Font {
        let scale: CGFloat
        switch level {
        case 1: scale = 1.9
        case 2: scale = 1.55
        case 3: scale = 1.3
        case 4: scale = 1.15
        case 5: scale = 1.05
        default: scale = 1.0
        }
        return .system(size: baseFontSize * scale, weight: .semibold)
    }

    var primary: Color { theme.color(.textPrimary) }
    var secondary: Color { theme.color(.textSecondary) }
    var separator: Color { theme.color(.separator) }
    var surface: Color { theme.color(.surfaceBackground) }
    var accent: Color { theme.accentColor }
}

// MARK: - Block rendering

/// Renders a single block (recursively, for quotes/lists).
struct MarkdownBlockView: View {
    let block: MarkdownBlock
    let style: ReadingStyle

    var body: some View {
        switch block {
        case .heading(let level, let inlines):
            inlineText(inlines)
                .font(style.headingFont(level: level))
                .foregroundStyle(style.primary)
                .padding(.top, level <= 2 ? Spacing.sm : 0)

        case .paragraph(let inlines):
            if let image = ParagraphImage(inlines: inlines) {
                MarkdownImageView(source: image.source, alt: image.alt, style: style)
            } else {
                inlineText(inlines)
                    .font(style.bodyFont)
                    .foregroundStyle(style.primary)
                    .tint(style.accent)
            }

        case .codeBlock(let language, let code):
            CodeBlockView(language: language, code: code, style: style)

        case .blockQuote(let children):
            BlockQuoteView(children: children, style: style)

        case .unorderedList(let items):
            ListView(items: items, ordered: nil, style: style)

        case .orderedList(let start, let items):
            ListView(items: items, ordered: start, style: style)

        case .thematicBreak:
            Divider().overlay(style.separator)

        case .table(let table):
            TableView(table: table, style: style)

        case .htmlBlock(let html):
            CodeBlockView(language: "html", code: html, style: style)
        }
    }

    @ViewBuilder
    private func inlineText(_ inlines: [MarkdownInline]) -> some View {
        Text(MarkdownInlineRenderer.attributedString(for: inlines))
            .textSelection(.enabled)
    }
}

// MARK: - Code block

private struct CodeBlockView: View {
    let language: String?
    let code: String
    let style: ReadingStyle

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if let language, !language.isEmpty {
                Text(language)
                    .font(.system(size: style.baseFontSize - 4, weight: .medium))
                    .foregroundStyle(style.secondary)
            }
            Text(code.hasSuffix("\n") ? String(code.dropLast()) : code)
                .font(style.codeFont)
                .foregroundStyle(style.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.surface, in: RoundedRectangle(cornerRadius: Radius.small))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.small)
                .stroke(style.separator, lineWidth: 1))
    }
}

// MARK: - Block quote

private struct BlockQuoteView: View {
    let children: [MarkdownBlock]
    let style: ReadingStyle

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(style.accent.opacity(0.6))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: Spacing.sm) {
                ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                    MarkdownBlockView(block: child, style: style)
                }
            }
        }
        .foregroundStyle(style.secondary)
    }
}

// MARK: - Lists

private struct ListView: View {
    let items: [MarkdownListItem]
    /// The first ordinal for an ordered list, or `nil` for a bulleted list.
    let ordered: Int?
    let style: ReadingStyle

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                    marker(for: item, index: index)
                        .font(style.bodyFont)
                        .foregroundStyle(style.secondary)
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        ForEach(Array(item.children.enumerated()), id: \.offset) { _, child in
                            MarkdownBlockView(block: child, style: style)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func marker(for item: MarkdownListItem, index: Int) -> some View {
        switch item.checkbox {
        case .checked:
            Image(systemName: "checkmark.square.fill")
                .foregroundStyle(style.accent)
        case .unchecked:
            Image(systemName: "square")
                .foregroundStyle(style.secondary)
        case nil:
            if let start = ordered {
                Text("\(start + index).")
            } else {
                Text("•")
            }
        }
    }
}

// MARK: - Table

private struct TableView: View {
    let table: MarkdownTable
    let style: ReadingStyle

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: Spacing.md, verticalSpacing: Spacing.xs) {
            GridRow {
                ForEach(Array(table.header.enumerated()), id: \.offset) { column, cell in
                    cellText(cell, column: column)
                        .font(style.bodyFont.weight(.semibold))
                        .foregroundStyle(style.primary)
                }
            }
            Divider().overlay(style.separator)
            ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { column, cell in
                        cellText(cell, column: column)
                            .font(style.bodyFont)
                            .foregroundStyle(style.primary)
                    }
                }
            }
        }
        .padding(Spacing.sm)
        .background(style.surface, in: RoundedRectangle(cornerRadius: Radius.small))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.small)
                .stroke(style.separator, lineWidth: 1))
    }

    @ViewBuilder
    private func cellText(_ inlines: [MarkdownInline], column: Int) -> some View {
        Text(MarkdownInlineRenderer.attributedString(for: inlines))
            .multilineTextAlignment(alignment(for: column))
            .gridColumnAlignment(horizontalAlignment(for: column))
    }

    private func alignment(for column: Int) -> TextAlignment {
        switch columnAlignment(column) {
        case .center: .center
        case .right: .trailing
        default: .leading
        }
    }

    private func horizontalAlignment(for column: Int) -> HorizontalAlignment {
        switch columnAlignment(column) {
        case .center: .center
        case .right: .trailing
        default: .leading
        }
    }

    private func columnAlignment(_ column: Int) -> MarkdownColumnAlignment? {
        table.columnAlignments.indices.contains(column) ? table.columnAlignments[column] : nil
    }
}

// MARK: - Images

/// A standalone-image paragraph (a paragraph that is effectively just one image).
private struct ParagraphImage {
    let source: String?
    let alt: String

    init?(inlines: [MarkdownInline]) {
        let meaningful = inlines.filter { inline in
            if case .text(let s) = inline, s.trimmingCharacters(in: .whitespaces).isEmpty {
                return false
            }
            if case .softBreak = inline { return false }
            return true
        }
        guard meaningful.count == 1, case .image(let source, let alt) = meaningful[0] else {
            return nil
        }
        self.source = source
        self.alt = alt
    }
}

/// Loads a vault-relative or remote image; shows alt text on failure.
private struct MarkdownImageView: View {
    let source: String?
    let alt: String
    let style: ReadingStyle

    var body: some View {
        if let url = resolvedURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                case .failure:
                    placeholder
                case .empty:
                    ProgressView()
                @unknown default:
                    placeholder
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Label(alt.isEmpty ? "Image" : alt, systemImage: "photo")
            .font(style.bodyFont)
            .foregroundStyle(style.secondary)
    }

    /// Resolves remote URLs directly; treats anything else as a path relative
    /// to the note's directory (security-scoped vault access already granted).
    private var resolvedURL: URL? {
        guard let source, !source.isEmpty else { return nil }
        if let url = URL(string: source), url.scheme != nil {
            return url
        }
        if let baseURL = style.baseURL {
            return URL(fileURLWithPath: source, relativeTo: baseURL)
        }
        return URL(string: source)
    }
}
