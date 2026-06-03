//
//  EditorDocument.swift
//  LumenEditor
//
//  Minimal in-memory document model backing the TextKit 2 editor host.
//
//  P1.10 scope: in-memory text plumbing only. Disk persistence (open/save),
//  autosave, and undo wiring are explicitly OUT OF SCOPE here (P1.4/P1.5/P1.11).
//

import Foundation
import Observation

/// An observable, in-memory text document for the editor host.
///
/// This is deliberately tiny: it holds the editor's current text so SwiftUI
/// views can bind to it. File loading/saving is handled elsewhere in later
/// Phase-1 tasks; this type never touches disk.
@MainActor
@Observable
public final class EditorDocument {
    /// The full text contents of the document.
    public var text: String

    /// Creates a document with optional initial contents.
    /// - Parameter text: The initial text. Defaults to empty.
    public init(text: String = "") {
        self.text = text
    }
}
