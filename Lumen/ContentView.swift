//
//  ContentView.swift
//  Lumen
//
//  The three-region application shell (P1.14):
//    • collapsible left sidebar (vault header + file-tree placeholder)
//    • center: a tab-bar strip (visual scaffold) above the TextKit 2 editor
//    • slim bottom status bar (placeholder)
//
//  Structure: a `NavigationSplitView` gives the collapsible sidebar + detail
//  (toggled by the View ▸ Toggle Sidebar command from P1.2). The tab strip is a
//  `.safeAreaInset(edge: .top)` on the detail; the status bar is a
//  `.safeAreaInset(edge: .bottom)` on the whole split view so it spans full
//  width. Chrome surfaces use real macOS 26 Liquid Glass (`.glassEffect`,
//  `GlassEffectContainer`, `.buttonStyle(.glass)`); colors/type/spacing come
//  from the P1.17 design tokens.
//
//  Region CONTENTS are deferred: real file tree = P1.15, functional tabs =
//  P1.16, status-bar metrics = P1.18.
//

import LumenCore
import LumenDesignSystem
import LumenEditor
import SwiftUI

struct ContentView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(ThemeManager.self) private var themeManager
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var editorText: String = SampleContent.welcomeMarkdown

    var body: some View {
        let theme = themeManager.theme
        return NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 380)
        } detail: {
            EditorRegion(text: $editorText, theme: theme)
                .safeAreaInset(edge: .top, spacing: 0) {
                    TabStripView(title: env.vault.current?.name)
                }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            StatusBarView()
        }
        .frame(minWidth: 720, minHeight: 460)
    }
}

// MARK: - Center editor region

/// The center region: the working TextKit 2 editor on a token-colored canvas.
private struct EditorRegion: View {
    @Binding var text: String
    let theme: Theme

    var body: some View {
        TextKit2EditorView(
            text: $text,
            highlightTheme: MarkdownHighlightTheme(theme: theme)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.color(.editorBackground))
    }
}

// MARK: - Tab strip (visual scaffold only — functional tabs are P1.16)

/// A non-functional tab strip placed above the editor as a layout scaffold.
/// Shows a single "current note" pill; real open/close/reorder tabs are P1.16.
private struct TabStripView: View {
    @Environment(ThemeManager.self) private var themeManager
    let title: String?
    @Namespace private var glassNamespace

    var body: some View {
        let theme = themeManager.theme
        return GlassEffectContainer {
            HStack(spacing: Spacing.sm) {
                CurrentTabPill(label: title ?? "Untitled", theme: theme)
                    .glassEffectID("current-tab", in: glassNamespace)

                Spacer()

                // Scaffold-only "new tab" affordance (wired up in P1.16).
                Button {
                    // No-op: functional tabs are P1.16.
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.glass)
                .disabled(true)
                .help("New tab (coming in a later update)")
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
        }
        .frame(height: 34)
        .frame(maxWidth: .infinity)
        .background(theme.color(.surfaceBackground).opacity(0.001))  // let glass read through
    }
}

/// The single placeholder tab pill.
private struct CurrentTabPill: View {
    let label: String
    let theme: Theme

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "doc.text")
                .font(.system(size: 11))
            Text(label)
                .font(Typography.font(.callout))
                .lineLimit(1)
        }
        .foregroundStyle(theme.color(.textPrimary))
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .glassChrome(in: .capsule)
    }
}

// MARK: - Sidebar (header + file-tree placeholder — real tree is P1.15)

/// Left sidebar: the vault header (P1.4) over a file-tree placeholder.
private struct SidebarView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        let theme = themeManager.theme
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            VaultHeader(vault: env.vault.current)
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.md)

            Divider()
                .overlay(theme.color(.separator))

            FileTreePlaceholder(hasVault: env.vault.current != nil, theme: theme)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The NavigationSplitView sidebar is already a native translucent
        // (Liquid Glass) surface; we layer token-colored content on top.
        .navigationTitle(env.vault.current?.name ?? "Lumen")
    }
}

/// Placeholder for the file tree (real tree + context menu is P1.15).
private struct FileTreePlaceholder: View {
    let hasVault: Bool
    let theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if hasVault {
                Label("No files yet", systemImage: "tray")
                    .font(Typography.font(.callout))
                    .foregroundStyle(theme.color(.textSecondary))
                Text("The file tree arrives soon.")
                    .font(Typography.font(.caption))
                    .foregroundStyle(theme.color(.textPlaceholder))
            } else {
                Label("Open a vault to begin", systemImage: "folder.badge.plus")
                    .font(Typography.font(.callout))
                    .foregroundStyle(theme.color(.textSecondary))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.md)
    }
}

/// Compact header describing the open vault (or its absence).
private struct VaultHeader: View {
    @Environment(ThemeManager.self) private var themeManager
    let vault: Vault?

    var body: some View {
        let theme = themeManager.theme
        return VStack(alignment: .leading, spacing: Spacing.xxs) {
            if let vault {
                Label(vault.name, systemImage: "folder")
                    .font(Typography.font(.headline))
                    .foregroundStyle(theme.color(.textPrimary))
                    .lineLimit(1)
                Text(vault.root.path)
                    .font(Typography.font(.caption))
                    .foregroundStyle(theme.color(.textSecondary))
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Label("No vault open", systemImage: "folder.badge.questionmark")
                    .font(Typography.font(.headline))
                    .foregroundStyle(theme.color(.textSecondary))
                Text("File ▸ Open Vault… (⇧⌘O)")
                    .font(Typography.font(.caption))
                    .foregroundStyle(theme.color(.textPlaceholder))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Status bar (slim placeholder — metrics are P1.18)

/// Slim bottom status bar. Placeholder only; word/char count, save state, and
/// the indexing indicator are P1.18.
private struct StatusBarView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        let theme = themeManager.theme
        return HStack(spacing: Spacing.sm) {
            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .foregroundStyle(theme.accentColor)
            Text(env.vault.current?.name ?? "No vault")
                .font(Typography.font(.caption))
                .foregroundStyle(theme.color(.textSecondary))
            Spacer()
            Text("Lumen")
                .font(Typography.font(.caption))
                .foregroundStyle(theme.color(.textPlaceholder))
        }
        .padding(.horizontal, Spacing.md)
        .frame(height: 26)
        .frame(maxWidth: .infinity)
        .glassChrome(in: .rect)
    }
}

#Preview {
    let env = AppEnvironment(vault: VaultManager(reopenLast: false))
    return ContentView()
        .environment(env)
        .environment(env.theme)
}
