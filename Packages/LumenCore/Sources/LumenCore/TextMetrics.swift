//
//  TextMetrics.swift
//  LumenCore
//
//  Pure word/character counting for the status bar (P1.18). Kept here so the
//  counting logic is unit-testable and reusable; the view debounces how often
//  it is invoked on large documents.
//

import Foundation

/// Word + character counts for a block of text.
public struct TextMetrics: Sendable, Equatable {
    public var words: Int
    public var characters: Int

    public init(words: Int, characters: Int) {
        self.words = words
        self.characters = characters
    }

    /// Empty counts (no document).
    public static let empty = TextMetrics(words: 0, characters: 0)

    /// Counts words and characters in `text`.
    ///
    /// - Characters: count of Swift `Character`s (grapheme clusters), so
    ///   multi-scalar emoji count as one.
    /// - Words: maximal runs separated by Unicode whitespace/newlines.
    public init(counting text: String) {
        self.characters = text.count
        var words = 0
        var inWord = false
        for character in text.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(character) {
                inWord = false
            } else if !inWord {
                inWord = true
                words += 1
            }
        }
        self.words = words
    }
}

/// The editor's save state, with a display label (P1.18).
public enum SaveState: Sendable, Equatable {
    case saved
    case unsaved

    public init(isDirty: Bool) {
        self = isDirty ? .unsaved : .saved
    }

    /// Localized status label.
    public var label: String {
        switch self {
        case .saved: String(localized: "Saved")
        case .unsaved: String(localized: "Unsaved changes")
        }
    }
}
