//
//  ContentView.swift
//  Lumen
//
//  Root shell: collapsible left sidebar · center editor area · slim bottom
//  status bar. P1.1 placeholder only — no real functionality yet.
//

import LumenCore
import LumenDesignSystem
import LumenEditor
import SwiftUI

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

/// Left sidebar — shows the current vault's name/path (file tree is P1.15).
private struct SidebarPlaceholder: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VaultHeader(vault: env.vault.current)
                .padding(12)
            Divider()
            Spacer()
            Text("File tree coming soon")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
            Spacer()
        }
        .navigationTitle(env.vault.current?.name ?? "Lumen")
    }
}

/// Compact header describing the open vault (or its absence).
private struct VaultHeader: View {
    let vault: Vault?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let vault {
                Label(vault.name, systemImage: "folder")
                    .font(.headline)
                    .lineLimit(1)
                Text(vault.root.path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Label("No vault open", systemImage: "folder.badge.questionmark")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("File ▸ Open Vault… (⇧⌘O)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
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
        .environment(AppEnvironment(vault: VaultManager(reopenLast: false)))
}
