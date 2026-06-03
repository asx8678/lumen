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

    /// Creates an editor host bound to the given text.
    /// - Parameters:
    ///   - text: A two-way binding to the document text.
    ///   - highlightTheme: Colors/fonts for syntax highlighting. Defaults to
    ///     the ad-hoc theme until design tokens (P1.17) inject one.
    public init(
        text: Binding<String>,
        highlightTheme: MarkdownHighlightTheme = .default
    ) {
        self._text = text
        self.highlightTheme = highlightTheme
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, theme: highlightTheme)
    }

    public func makeNSView(context: Context) -> NSScrollView {
        // TextKit 2: passing `usingTextLayoutManager: true` builds the modern
        // NSTextLayoutManager / NSTextContentStorage stack with viewport layout.
        let textView = NSTextView(usingTextLayoutManager: true)
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textContainerInset = NSSize(width: 12, height: 12)

        // Resize behavior suitable for a vertically-scrolling editor.
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude)
        if let container = textView.textContainer {
            container.widthTracksTextView = true
            container.containerSize = NSSize(
                width: 0,
                height: CGFloat.greatestFiniteMagnitude)
        }

        // Seed initial contents through the TextKit 2 content storage.
        context.coordinator.setText(text, in: textView)

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

        // Highlight the initial viewport.
        context.coordinator.highlightViewport(in: textView)
        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        // Only push programmatic changes; skip when the user is the source to
        // avoid clobbering the selection / insertion point mid-edit.
        if !context.coordinator.isApplyingUserEdit, textView.string != text {
            context.coordinator.setText(text, in: textView)
        }
    }

    // MARK: - Coordinator

    /// Bridges `NSTextView` edits back into the SwiftUI `Binding<String>`.
    @MainActor
    public final class Coordinator: NSObject, NSTextViewDelegate {
        private let text: Binding<String>
        private let theme: MarkdownHighlightTheme
        private let highlighter = MarkdownHighlighter()
        nonisolated(unsafe) private var scrollObserver: NSObjectProtocol?

        /// True while a user edit is being propagated, so `updateNSView`
        /// does not echo the change back and reset the cursor.
        fileprivate var isApplyingUserEdit = false

        init(text: Binding<String>, theme: MarkdownHighlightTheme) {
            self.text = text
            self.theme = theme
        }

        deinit {
            if let scrollObserver {
                NotificationCenter.default.removeObserver(scrollObserver)
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

        /// Resets and applies highlighting attributes for `range`.
        private func applyHighlight(_ range: NSRange, in textView: NSTextView) {
            guard let storage = textView.textContentStorage?.textStorage else { return }
            let ns = storage.string as NSString
            let scan = NSIntersectionRange(range, NSRange(location: 0, length: ns.length))
            guard scan.length > 0 else { return }

            let spans = highlighter.styledRanges(in: storage.string, range: scan, theme: theme)
            storage.beginEditing()
            // Reset to body style first so stale colors clear when markers change.
            storage.setAttributes(
                [
                    .foregroundColor: theme.bodyColor,
                    .font: theme.baseFont,
                ], range: scan)
            for span in spans {
                let clamped = NSIntersectionRange(span.range, scan)
                if clamped.length > 0 {
                    storage.addAttributes(span.attributes, range: clamped)
                }
            }
            storage.endEditing()
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
        }
    }
}
