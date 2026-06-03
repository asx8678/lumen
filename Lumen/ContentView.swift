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

// Token-driven theming (P1.17) applied to the existing P1.1/P1.4 shell.

/// The top-level three-region application shell.
///
/// Layout:
/// - A collapsible left sidebar (file tree placeholder).
/// - A center editor area (TextKit 2 host placeholder).
/// - A slim bottom status bar.
struct ContentView: View {
    @Environment(ThemeManager.self) private var themeManager
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var editorText: String = SampleContent.welcomeMarkdown

    var body: some View {
        let theme = themeManager.theme
        return VStack(spacing: 0) {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                SidebarPlaceholder()
                    .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 360)
            } detail: {
                TextKit2EditorView(
                    text: $editorText,
                    highlightTheme: MarkdownHighlightTheme(theme: theme)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.color(.editorBackground))
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
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        let theme = themeManager.theme
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            VaultHeader(vault: env.vault.current)
                .padding(Spacing.md)
            Divider()
            Spacer()
            Text("File tree coming soon")
                .font(Typography.font(.caption))
                .foregroundStyle(theme.color(.textPlaceholder))
                .frame(maxWidth: .infinity)
            Spacer()
        }
        .background(theme.color(.sidebarBackground))
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
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        let theme = themeManager.theme
        return HStack {
            Text("Ready")
                .font(Typography.font(.caption))
                .foregroundStyle(theme.color(.textSecondary))
            Spacer()
            Text("LumenCore \(LumenCore.version)")
                .font(Typography.font(.caption))
                .foregroundStyle(theme.color(.textPlaceholder))
        }
        .padding(.horizontal, Spacing.md)
        .frame(height: 24)
        .background(theme.color(.surfaceBackground))
    }
}

#Preview {
    let env = AppEnvironment(vault: VaultManager(reopenLast: false))
    return ContentView()
        .environment(env)
        .environment(env.theme)
}
