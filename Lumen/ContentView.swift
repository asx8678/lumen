//
//  ContentView.swift
//  Lumen
//
//  Root shell: collapsible left sidebar · center editor area · slim bottom
//  status bar. P1.1 placeholder only — no real functionality yet.
//

import SwiftUI
import LumenCore
import LumenDesignSystem
import LumenEditor

/// The top-level three-region application shell.
///
/// Layout:
/// - A collapsible left sidebar (file tree placeholder).
/// - A center editor area (TextKit 2 host placeholder).
/// - A slim bottom status bar.
struct ContentView: View {
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var editorText: String = SampleContent.welcomeMarkdown

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                SidebarPlaceholder()
                    .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 360)
            } detail: {
                TextKit2EditorView(text: $editorText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()
            StatusBarPlaceholder()
        }
        .frame(minWidth: 640, minHeight: 400)
    }
}

// MARK: - Placeholder regions

/// Left sidebar placeholder — will host the vault file tree.
private struct SidebarPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading) {
            Spacer()
            Text("Sidebar")
                .font(.headline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
            Spacer()
        }
        .navigationTitle("Lumen")
    }
}

/// Slim bottom status bar placeholder.
private struct StatusBarPlaceholder: View {
    var body: some View {
        HStack {
            Text("Ready")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text("LumenCore \(LumenCore.version)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .frame(height: 24)
    }
}

#Preview {
    ContentView()
}
