//
//  TextKit2EditorView.swift
//  LumenEditor
//
//  A SwiftUI NSViewRepresentable hosting an NSTextView built on the TextKit 2
//  stack (NSTextLayoutManager + NSTextContentStorage) with viewport-based
//  layout. P1.10 risk spike: large-document performance is a first-class
//  concern here.
//
//  SCOPE: editor host + two-way text binding + lightweight Markdown
//  highlighting (P1.12). Autosave/undo wiring (P1.11) and typography controls
//  (P1.13) remain out of scope; NSTextView's built-in undo is left enabled.
//  Highlighting is viewport-scoped: only the visible range / changed paragraph
//  is re-styled, never the whole document.
//

import AppKit
import SwiftUI

/// A SwiftUI wrapper around a TextKit 2 `NSTextView`.
///
/// The text view is constructed with `usingTextLayoutManager: true`, which
/// installs an `NSTextLayoutManager` / `NSTextContentStorage` pair and performs
/// viewport-based (lazy) layout — the legacy TextKit 1 `layoutManager` path is
/// never instantiated.
///
/// Two-way editing flows through a `Binding<String>`: programmatic changes to
/// the binding are pushed into the content storage, and user edits are reported
/// back via the coordinator's `NSTextViewDelegate` conformance.
@MainActor
public struct TextKit2EditorView: NSViewRepresentable {
    /// The text being edited, bound to the owning SwiftUI view.
    @Binding public var text: String

    /// Styling configuration for the Markdown highlighter (P1.17 seam).
    public var highlightTheme: MarkdownHighlightTheme

    /// Adjustable typography: font kind/size, line width, line spacing (P1.13).
    public var typography: EditorTypography

    /// Called when the editor loses first-responder focus (write-on-blur, P1.11).
    public var onBlur: (() -> Void)?

    /// Feature flag for the P2.2.1 inline live-preview SPIKE. When `false`
    /// (the default) the editor behaves exactly as the shipping Phase-1
    /// highlighter; when `true` it conceals Style-class Markdown markers on
    /// inactive logical lines and reveals them on the caret/selection's line.
    public var enableLivePreview: Bool

    /// Creates an editor host bound to the given text.
    /// - Parameters:
    ///   - text: A two-way binding to the document text.
    ///   - highlightTheme: Colors/fonts for syntax highlighting. Defaults to
    ///     the ad-hoc theme until design tokens (P1.17) inject one.
    ///   - onBlur: Invoked when editing ends / focus is lost (autosave flush).
    public init(
        text: Binding<String>,
        highlightTheme: MarkdownHighlightTheme = .default,
        typography: EditorTypography = .default,
        enableLivePreview: Bool = false,
        onBlur: (() -> Void)? = nil
    ) {
        self._text = text
        self.highlightTheme = highlightTheme
        self.typography = typography
        self.enableLivePreview = enableLivePreview
        self.onBlur = onBlur
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text, theme: highlightTheme, typography: typography,
            enableLivePreview: enableLivePreview, onBlur: onBlur)
    }

    public func makeNSView(context: Context) -> NSScrollView {
        // TextKit 2: passing `usingTextLayoutManager: true` builds the modern
        // NSTextLayoutManager / NSTextContentStorage stack with viewport layout.
        let textView = NSTextView(usingTextLayoutManager: true)
        textView.delegate = context.coordinator
        // Observe character edits to keep the tree-sitter parse tree in sync
        // (P2.0.1). This runs off the keystroke hot path and does not render.
        textView.textContentStorage?.textStorage?.delegate = context.coordinator
        // P2.2.1 live-preview SPIKE: install the concealment controller as the
        // content-storage delegate. It is INERT unless the feature flag is on,
        // so the default editor path is unaffected.
        context.coordinator.livePreviewController.isEnabled = enableLivePreview
        textView.textContentStorage?.delegate = context.coordinator.livePreviewController
        // P1.21 UI test hook: lets XCUITest locate the editor text area.
        textView.setAccessibilityIdentifier("editor-textview")
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = typography.resolvedFont()

        // Resize behavior suitable for a vertically-scrolling editor.
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude)

        // Apply the chosen font, line width (container + centering) and line
        // spacing (typing attributes) before seeding contents.
        context.coordinator.applyTypography(typography, to: textView)

        // Recenter the readable column when the view is resized.
        textView.postsFrameChangedNotifications = true
        context.coordinator.observeFrame(of: textView)

        // Seed initial contents through the TextKit 2 content storage, then
        // clear undo so the programmatic load is NOT undoable — each document
        // (tab) starts with a clean per-view undo history (P1.11).
        context.coordinator.setText(text, in: textView)
        textView.undoManager?.removeAllActions()

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true

        // Re-highlight the visible range as the user scrolls (viewport-scoped).
        let clipView = scrollView.contentView
        clipView.postsBoundsChangedNotifications = true
        context.coordinator.observeScroll(of: clipView, textView: textView)

        // Seed the parse tree from the initial contents (P2.0.1) BEFORE the
        // first highlight pass: tree-sitter highlighting (P2.0.2) awaits this
        // parse task, so the initial viewport styles from a populated tree.
        context.coordinator.seedParse(with: textView)
        // Highlight the initial viewport.
        context.coordinator.highlightViewport(in: textView)
        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        // Keep the latest highlight theme so re-styling uses current colors/font.
        context.coordinator.updateTheme(highlightTheme)

        // Re-apply typography only when it actually changed (an explicit user
        // action), never per keystroke — keeps large-doc typing/scroll cheap.
        if context.coordinator.typography != typography {
            context.coordinator.applyTypography(typography, to: textView)
        }

        // Only push programmatic changes; skip when the user is the source to
        // avoid clobbering the selection / insertion point mid-edit.
        if !context.coordinator.isApplyingUserEdit, textView.string != text {
            context.coordinator.setText(text, in: textView)
        }
    }

    // MARK: - Coordinator

    /// Bridges `NSTextView` edits back into the SwiftUI `Binding<String>`.
    @MainActor
    public final class Coordinator: NSObject, NSTextViewDelegate,
        @preconcurrency NSTextStorageDelegate
    {
        private let text: Binding<String>
        private var theme: MarkdownHighlightTheme
        /// The typography last applied to the text view (P1.13).
        fileprivate var typography: EditorTypography
        private let onBlur: (() -> Void)?
        private let highlighter = MarkdownTreeSitterHighlighter()

        // MARK: - Live preview (P2.2.1 spike, feature-flagged)

        /// Whether inline live-preview concealment is active for this editor.
        let enableLivePreview: Bool
        /// Owns the conceal/reveal display substitution (content-storage
        /// delegate). Inert while `enableLivePreview` is `false`.
        let livePreviewController = LivePreviewConcealmentController()
        nonisolated(unsafe) private var scrollObserver: NSObjectProtocol?
        nonisolated(unsafe) private var frameObserver: NSObjectProtocol?

        // MARK: - Parse backbone (P2.0.1)

        /// Incremental tree-sitter parser kept in sync with the document. It
        /// runs OFF the keystroke hot path and does NOT (yet) drive rendering —
        /// it exists so later tasks (highlighting, live preview, folding) can
        /// query an accurate, incrementally-maintained parse tree.
        let markdownParser: MarkdownTreeSitterParser? = try? MarkdownTreeSitterParser()
        /// Serial chain of background parse tasks, preserving edit order.
        private var parseTask: Task<Void, Never>?

        /// True while a user edit is being propagated, so `updateNSView`
        /// does not echo the change back and reset the cursor.
        fileprivate var isApplyingUserEdit = false

        init(
            text: Binding<String>,
            theme: MarkdownHighlightTheme,
            typography: EditorTypography,
            enableLivePreview: Bool,
            onBlur: (() -> Void)?
        ) {
            self.text = text
            self.theme = theme
            self.typography = typography
            self.enableLivePreview = enableLivePreview
            self.onBlur = onBlur
        }

        deinit {
            if let scrollObserver {
                NotificationCenter.default.removeObserver(scrollObserver)
            }
            if let frameObserver {
                NotificationCenter.default.removeObserver(frameObserver)
            }
        }

        /// Updates the highlight theme so future re-styling uses current colors
        /// and base font (kept in sync with the editor's typography).
        func updateTheme(_ newTheme: MarkdownHighlightTheme) {
            theme = newTheme
        }

        // MARK: - Typography (P1.13)

        /// Applies font, readable line width, and line spacing to the text view,
        /// then re-highlights the viewport so colors/bold/italic recompose.
        func applyTypography(_ newTypography: EditorTypography, to textView: NSTextView) {
            typography = newTypography
            theme.baseFont = newTypography.resolvedFont()
            theme.paragraphStyle = newTypography.resolvedParagraphStyle()

            textView.font = theme.baseFont
            textView.typingAttributes = [
                .font: theme.baseFont,
                .foregroundColor: theme.bodyColor,
                .paragraphStyle: theme.paragraphStyle,
            ]

            // Single full-document baseline pass for font + paragraph style
            // (cheap: one batched attribute run, only on explicit changes).
            if let storage = textView.textContentStorage?.textStorage {
                let full = NSRange(location: 0, length: (storage.string as NSString).length)
                if full.length > 0 {
                    storage.beginEditing()
                    storage.addAttribute(.font, value: theme.baseFont, range: full)
                    storage.addAttribute(.paragraphStyle, value: theme.paragraphStyle, range: full)
                    storage.endEditing()
                }
            }

            configureLineWidth(newTypography.lineWidth, in: textView)
            highlightViewport(in: textView)
        }

        /// Configures the text container width + horizontal centering for the
        /// readable max line width ("unlimited" tracks the full text view width).
        func configureLineWidth(_ lineWidth: EditorTypography.LineWidth, in textView: NSTextView) {
            guard let container = textView.textContainer else { return }
            let vertical: CGFloat = 12
            if let maxWidth = lineWidth.points {
                container.widthTracksTextView = false
                container.size = NSSize(width: maxWidth, height: CGFloat.greatestFiniteMagnitude)
                let available = textView.bounds.width
                let inset = max(12, (available - maxWidth) / 2)
                textView.textContainerInset = NSSize(width: inset, height: vertical)
            } else {
                container.widthTracksTextView = true
                container.size = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
                textView.textContainerInset = NSSize(width: 12, height: vertical)
            }
        }

        /// Observes frame changes to recenter the readable column on resize.
        func observeFrame(of textView: NSTextView) {
            frameObserver = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: textView,
                queue: .main
            ) { [weak self, weak textView] _ in
                MainActor.assumeIsolated {
                    guard let self, let textView else { return }
                    self.configureLineWidth(self.typography.lineWidth, in: textView)
                }
            }
        }

        /// Observes clip-view scrolling to re-highlight the new viewport.
        func observeScroll(of clipView: NSClipView, textView: NSTextView) {
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak self, weak textView] _ in
                MainActor.assumeIsolated {
                    guard let self, let textView else { return }
                    self.highlightViewport(in: textView)
                }
            }
        }

        // MARK: - Highlighting (viewport-scoped)

        /// Re-highlights only the currently visible character range.
        func highlightViewport(in textView: NSTextView) {
            guard let range = viewportCharRange(in: textView) else { return }
            applyHighlight(range, in: textView)
        }

        /// Re-highlights the paragraph containing the insertion point.
        func highlightActiveParagraph(in textView: NSTextView) {
            let ns = textView.string as NSString
            guard ns.length > 0 else { return }
            let caret = min(textView.selectedRange().location, ns.length)
            let paragraph = ns.paragraphRange(for: NSRange(location: caret, length: 0))
            applyHighlight(paragraph, in: textView)
        }

        /// Computes the visible character range using the TextKit 2 layout
        /// fragments at the top and bottom of the visible rect (no full scan).
        private func viewportCharRange(in textView: NSTextView) -> NSRange? {
            guard let layoutManager = textView.textLayoutManager,
                let contentManager = textView.textContentStorage
            else { return nil }
            let visible = textView.visibleRect
            guard visible.height > 0,
                let topFragment = layoutManager.textLayoutFragment(
                    for: CGPoint(x: 0, y: visible.minY)),
                let bottomFragment = layoutManager.textLayoutFragment(
                    for: CGPoint(x: 0, y: visible.maxY))
            else { return nil }
            let start = topFragment.rangeInElement.location
            let end = bottomFragment.rangeInElement.endLocation
            let location = contentManager.offset(
                from: contentManager.documentRange.location, to: start)
            let length = contentManager.offset(from: start, to: end)
            guard location != NSNotFound, length > 0 else { return nil }
            let ns = textView.string as NSString
            // Expand to paragraph boundaries so partial fragments style fully.
            return ns.paragraphRange(for: NSRange(location: location, length: length))
        }

        /// Resets and applies tree-sitter-driven highlighting for `range`.
        ///
        /// Highlighting is computed from the parser actor's incrementally
        /// maintained parse tree, so the (potentially non-trivial) parse work
        /// stays OFF the keystroke hot path. We await any in-flight reparse
        /// (`parseTask`) so the queried nodes reflect the latest text, then
        /// query the viewport-scoped node set and overlay attributes back on
        /// the main actor. Applying attributes is an attribute-only edit, so it
        /// does not trigger a spurious reparse.
        private func applyHighlight(_ range: NSRange, in textView: NSTextView) {
            guard let parser = markdownParser,
                let storage = textView.textContentStorage?.textStorage
            else { return }
            let ns = storage.string as NSString
            let scan = NSIntersectionRange(range, NSRange(location: 0, length: ns.length))
            guard scan.length > 0 else { return }

            let theme = self.theme
            let highlighter = self.highlighter
            let pending = parseTask
            Task { @MainActor [weak textView] in
                // Wait for the latest scheduled reparse so node ranges are
                // consistent with the current document text.
                await pending?.value
                let nodes = await parser.nodes(in: scan)
                guard let textView,
                    let storage = textView.textContentStorage?.textStorage
                else { return }
                // Re-clamp against the (possibly changed) current length.
                let current = NSRange(
                    location: 0, length: (storage.string as NSString).length)
                let apply = NSIntersectionRange(scan, current)
                guard apply.length > 0 else { return }

                let spans = highlighter.styledRanges(for: nodes, theme: theme)
                storage.beginEditing()
                // Reset to body style first so stale colors clear when markers
                // change. The paragraph style (line spacing, P1.13) is part of
                // the baseline; highlighter spans only overlay color + bold/
                // italic font, so typography and syntax highlighting compose
                // cleanly.
                storage.setAttributes(
                    [
                        .foregroundColor: theme.bodyColor,
                        .font: theme.baseFont,
                        .paragraphStyle: theme.paragraphStyle,
                    ], range: apply)
                for span in spans {
                    let clamped = NSIntersectionRange(span.range, apply)
                    if clamped.length > 0 {
                        storage.addAttributes(span.attributes, range: clamped)
                    }
                }
                storage.endEditing()
            }
        }

        /// Replaces the text view's contents via the TextKit 2 content storage.
        func setText(_ newText: String, in textView: NSTextView) {
            if let storage = textView.textContentStorage?.textStorage {
                storage.replaceCharacters(
                    in: NSRange(
                        location: 0,
                        length: (textView.string as NSString).length),
                    with: newText
                )
            } else {
                textView.string = newText
            }
            // Re-highlight the now-visible viewport after a programmatic load.
            highlightViewport(in: textView)
        }

        public func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            isApplyingUserEdit = true
            text.wrappedValue = textView.string
            // Re-style only the edited paragraph (cheap, bounded).
            highlightActiveParagraph(in: textView)
            isApplyingUserEdit = false
            // Markers may have appeared/closed on the edited line — refresh the
            // concealment set for the live-preview spike (no-op when disabled).
            recomputeConcealment(in: textView)
        }

        // MARK: - Live-preview concealment (P2.2.1 spike)

        /// Recomputes, for the live-preview feature, which Style-class markers
        /// in the viewport should be concealed given the current selection,
        /// then nudges only the affected range to re-query the display string.
        ///
        /// Viewport-scoped and inert unless `enableLivePreview` is set. The
        /// parse + node query run on the parser actor (off the hot path); the
        /// active-line set is diffed via `LivePreviewConcealmentController` so
        /// we only invalidate layout when the concealed set actually changes.
        func recomputeConcealment(in textView: NSTextView) {
            guard enableLivePreview,
                let parser = markdownParser,
                let storage = textView.textContentStorage?.textStorage,
                let viewport = viewportCharRange(in: textView)
            else { return }
            let ns = storage.string as NSString
            let scan = NSIntersectionRange(
                viewport, NSRange(location: 0, length: ns.length))
            guard scan.length > 0 else { return }
            let selections = textView.selectedRanges.map(\.rangeValue)
            let controller = livePreviewController
            let pending = parseTask
            Task { @MainActor [weak textView] in
                await pending?.value
                let nodes = await parser.nodes(in: scan)
                guard let textView,
                    let storage = textView.textContentStorage?.textStorage
                else { return }
                let current = storage.string as NSString
                let clamp = NSIntersectionRange(
                    scan, NSRange(location: 0, length: current.length))
                guard clamp.length > 0 else { return }
                let (concealed, _) = LivePreviewDecorations.resolve(
                    in: current, selections: selections, nodes: nodes)
                guard controller.update(concealed: concealed) else { return }
                // Mark the viewport's attributes dirty (NOT characters) so the
                // content storage re-queries the concealing delegate without
                // triggering a tree-sitter reparse.
                storage.beginEditing()
                storage.edited(.editedAttributes, range: clamp, changeInLength: 0)
                storage.endEditing()
            }
        }

        public func textViewDidChangeSelection(_ notification: Notification) {
            guard enableLivePreview,
                let textView = notification.object as? NSTextView
            else { return }
            recomputeConcealment(in: textView)
        }

        // MARK: - NSTextStorageDelegate (parse backbone, P2.0.1)

        /// Captures character edits and schedules an incremental reparse on the
        /// parser actor, off the keystroke hot path. Attribute-only edits (e.g.
        /// highlighting) are ignored so they don't trigger spurious reparses.
        public func textStorage(
            _ textStorage: NSTextStorage,
            didProcessEditing editedMask: NSTextStorageEditActions,
            range editedRange: NSRange,
            changeInLength delta: Int
        ) {
            guard editedMask.contains(.editedCharacters), let parser = markdownParser else {
                return
            }
            let edit = MarkdownTextEdit(editedRange: editedRange, changeInLength: delta)
            let newText = textStorage.string
            let previous = parseTask
            parseTask = Task {
                await previous?.value
                await parser.applyEdit(edit, newText: newText)
            }
        }

        /// Seeds the parse tree from the current contents (programmatic load).
        func seedParse(with textView: NSTextView) {
            guard let parser = markdownParser else { return }
            let text = textView.string
            let previous = parseTask
            parseTask = Task {
                await previous?.value
                await parser.parse(text)
            }
        }

        /// Editor lost focus — flush any pending autosave (P1.11).
        public func textDidEndEditing(_ notification: Notification) {
            onBlur?()
        }
    }
}
