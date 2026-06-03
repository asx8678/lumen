//
//  LivePreviewBlockChrome.swift
//  LumenEditor
//
//  P2.2.1c (lumen-nmm.19) — the TextKit 2 *mechanism* that draws block-level
//  live-preview CHROME that pure marker concealment can't express:
//  * blockquote left accent bar(s) (one per nesting level), and
//  * the shaded background box behind fenced / indented code.
//
//  Mechanism: an `NSTextLayoutManagerDelegate` (`LivePreviewBlockChromeProvider`)
//  vends a custom `NSTextLayoutFragment` subclass for paragraphs that intersect
//  a blockquote or code region. The fragment overrides `draw(at:in:)` to paint
//  its chrome BEHIND the text (then calls `super` to draw the glyphs on top), so
//  existing tree-sitter highlighting inside code fences keeps working untouched.
//
//  Geometry correctness under concealment: the bars and box are drawn from the
//  fragment's own `layoutFragmentFrame`, which TextKit 2 computes from the
//  (possibly shortened) DISPLAY string produced by the content-storage delegate.
//  So even though concealing `> ` shortens a display line, the chrome height /
//  baseline always matches what is actually laid out — no separate measurement
//  that could drift. Indentation is applied as paragraph-style head indent on
//  the same display string, and the bars are spaced on the SAME `unit`, so bar
//  columns line up with the indent gutter regardless of concealment.
//
//  Inert unless the live-preview feature flag installs the delegate, so the
//  default shipping editor path is byte-for-byte unchanged.
//

import AppKit

/// The chrome a layout fragment should paint behind its text.
enum LivePreviewBlockChrome: Equatable {
    /// `count` blockquote accent bars spaced by `unit` points, in `color`.
    case blockquoteBars(count: Int, unit: CGFloat, color: NSColor)
    /// A shaded code-block box of `color`, optionally combined with bars when a
    /// code block is nested inside a quote (rare but handled).
    case codeBox(color: NSColor)
}

/// A layout fragment that draws block-level live-preview chrome behind its text.
final class LivePreviewBlockLayoutFragment: NSTextLayoutFragment {
    /// The chrome to draw; multiple entries stack (e.g. a box plus bars).
    var chrome: [LivePreviewBlockChrome] = []
    /// Full container width, so the code box spans the readable column.
    var containerWidth: CGFloat = 0

    override func draw(at point: CGPoint, in context: CGContext) {
        let frame = layoutFragmentFrame
        // Local rect: `draw(at:)` is called with the fragment origin, and glyph
        // geometry is relative to that origin, so chrome uses a zero-origin rect
        // of the fragment's own size (height always matches the laid-out lines).
        let height = frame.height
        for layer in chrome {
            switch layer {
            case .codeBox(let color):
                let width = containerWidth > 0 ? containerWidth : frame.width
                let box = CGRect(
                    x: point.x - frame.minX, y: point.y,
                    width: width, height: height)
                context.saveGState()
                context.setFillColor(color.cgColor)
                context.fill(box)
                context.restoreGState()
            case .blockquoteBars(let count, let unit, let color):
                context.saveGState()
                context.setFillColor(color.cgColor)
                let barWidth: CGFloat = 3
                for level in 0..<count {
                    // Place each bar at the leading edge of its indent column.
                    let x = point.x - frame.minX + CGFloat(level) * unit + 2
                    let bar = CGRect(x: x, y: point.y, width: barWidth, height: height)
                    context.fill(bar)
                }
                context.restoreGState()
            }
        }
        super.draw(at: point, in: context)
    }
}

/// Vends `LivePreviewBlockLayoutFragment`s for paragraphs that intersect a
/// blockquote or code region, so TextKit 2 draws the bars / box.
@MainActor
final class LivePreviewBlockChromeProvider: NSObject, @preconcurrency NSTextLayoutManagerDelegate {
    /// Master switch — mirrors the editor's `enableLivePreview` flag.
    var isEnabled = false

    /// Blockquote regions (document UTF-16 coordinates) and their depths.
    private(set) var blockquoteRegions: [LivePreviewBlockDecorations.BlockquoteRegion] = []
    /// Code-block regions (document UTF-16 coordinates).
    private(set) var codeRegions: [LivePreviewBlockDecorations.CodeBlockRegion] = []

    /// The indent unit (points) used both for blockquote bar spacing and list
    /// indentation, so columns align.
    var indentUnit: CGFloat = 18
    /// Bar color (blockquote accent).
    var barColor: NSColor = .secondaryLabelColor
    /// Code-box fill color (a design-system surface).
    var codeBoxColor: NSColor = .quaternaryLabelColor
    /// Container width for the code box.
    var containerWidth: CGFloat = 0

    /// Replaces the region model. Returns `true` if anything changed (so the
    /// caller can invalidate layout for the affected viewport only).
    @discardableResult
    func update(
        blockquotes: [LivePreviewBlockDecorations.BlockquoteRegion],
        codeBlocks: [LivePreviewBlockDecorations.CodeBlockRegion]
    ) -> Bool {
        guard blockquotes != blockquoteRegions || codeBlocks != codeRegions else {
            return false
        }
        blockquoteRegions = blockquotes
        codeRegions = codeBlocks
        return true
    }

    func reset() {
        blockquoteRegions = []
        codeRegions = []
    }

    // MARK: - NSTextLayoutManagerDelegate

    func textLayoutManager(
        _ textLayoutManager: NSTextLayoutManager,
        textLayoutFragmentFor location: NSTextLocation,
        in textElement: NSTextElement
    ) -> NSTextLayoutFragment {
        let standard = NSTextLayoutFragment(
            textElement: textElement, range: textElement.elementRange)
        guard isEnabled, !blockquoteRegions.isEmpty || !codeRegions.isEmpty,
            let contentManager = textLayoutManager.textContentManager
        else { return standard }

        // Map the element's start to a document UTF-16 offset.
        let offset = contentManager.offset(
            from: contentManager.documentRange.location, to: location)
        guard offset != NSNotFound else { return standard }

        var chrome: [LivePreviewBlockChrome] = []
        if codeRegions.contains(where: { contains($0.range, offset) }) {
            chrome.append(.codeBox(color: codeBoxColor))
        }
        let depth = LivePreviewBlockDecorations.blockquoteDepth(
            at: offset, regions: blockquoteRegions)
        if depth > 0 {
            chrome.append(
                .blockquoteBars(count: depth, unit: indentUnit, color: barColor))
        }
        guard !chrome.isEmpty else { return standard }

        let fragment = LivePreviewBlockLayoutFragment(
            textElement: textElement, range: textElement.elementRange)
        fragment.chrome = chrome
        fragment.containerWidth = containerWidth
        return fragment
    }

    private func contains(_ range: NSRange, _ offset: Int) -> Bool {
        offset >= range.location && offset < NSMaxRange(range)
    }
}
