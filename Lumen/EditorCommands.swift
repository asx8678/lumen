//
//  EditorCommands.swift
//  Lumen
//
//  The View ▸ Editor typography submenu (P1.13): monospace/proportional toggle,
//  font size +/-/reset, and a line-width cycle. These drive the
//  `EditorTypographyStore`; the full settings pane is P1.19.
//

import LumenEditor
import SwiftUI

/// Lightweight typography adjusters in the View menu.
struct EditorCommands: Commands {
    let env: AppEnvironment

    private var store: EditorTypographyStore { env.editorTypography }

    var body: some Commands {
        CommandMenu("Editor") {
            Button(fontKindLabel) { store.toggleFontKind() }
                .keyboardShortcut("m", modifiers: [.command, .shift])

            Divider()

            Button("Increase Font Size") { store.increaseFontSize() }
                .keyboardShortcut("+", modifiers: [.command])
            Button("Decrease Font Size") { store.decreaseFontSize() }
                .keyboardShortcut("-", modifiers: [.command])
            Button("Reset Font Size") { store.resetFontSize() }
                .keyboardShortcut("0", modifiers: [.command])

            Divider()

            Button("Cycle Line Width (\(lineWidthLabel))") { store.cycleLineWidth() }
                .keyboardShortcut("l", modifiers: [.command, .shift])
        }
    }

    private var fontKindLabel: String {
        store.typography.fontKind == .monospace
            ? "Use Proportional Font" : "Use Monospace Font"
    }

    private var lineWidthLabel: String {
        store.typography.lineWidth.rawValue.capitalized
    }
}
