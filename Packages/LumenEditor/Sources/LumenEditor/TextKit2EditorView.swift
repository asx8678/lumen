//
//  TextKit2EditorView.swift
//  LumenEditor
//
//  A SwiftUI NSViewRepresentable hosting an NSTextView built on the TextKit 2
//  stack (NSTextLayoutManager + NSTextContentStorage) with viewport-based
//  layout. P1.10 risk spike: large-document performance is a first-class
//  concern here.
//
//  SCOPE: editor host + two-way text binding only. Syntax highlighting (P1.12),
//  autosave/undo wiring (P1.11), and typography controls (P1.13) are out of
//  scope; NSTextView's built-in undo is left enabled but not customized.
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

    /// Creates an editor host bound to the given text.
    /// - Parameter text: A two-way binding to the document text.
    public init(text: Binding<String>) {
        self._text = text
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
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
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        if let container = textView.textContainer {
            container.widthTracksTextView = true
            container.containerSize = NSSize(width: 0,
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

        /// True while a user edit is being propagated, so `updateNSView`
        /// does not echo the change back and reset the cursor.
        fileprivate var isApplyingUserEdit = false

        init(text: Binding<String>) {
            self.text = text
        }

        /// Replaces the text view's contents via the TextKit 2 content storage.
        func setText(_ newText: String, in textView: NSTextView) {
            if let storage = textView.textContentStorage,
               let documentRange = textView.textLayoutManager?.documentRange {
                storage.textStorage?.replaceCharacters(
                    in: NSRange(location: 0,
                                length: (textView.string as NSString).length),
                    with: newText
                )
                _ = documentRange  // viewport layout is driven lazily by TextKit 2
            } else {
                textView.string = newText
            }
        }

        public func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            isApplyingUserEdit = true
            text.wrappedValue = textView.string
            isApplyingUserEdit = false
        }
    }
}
