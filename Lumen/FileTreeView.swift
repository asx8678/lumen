//
//  FileTreeView.swift
//  Lumen
//
//  The sidebar file tree: folders + .md files (attachments greyed), expandable,
//  with a right-click file-op context menu. Selecting a Markdown file loads it
//  into the editor via the open-document model.
//
//  Obsidian-style restyle (lumen-p2b): a custom recursive tree (replacing the
//  native `List`/`OutlineGroup`) gives us full control over a SOLID surface,
//  13px rows, per-level indentation, neutral hover/active washes, rounded
//  selection, and a "collapse all" affordance — without the native sidebar
//  List's translucency or accent-filled selection.
//

import LumenCore
import LumenDesignSystem
import SwiftUI

struct FileTreeView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(ThemeManager.self) private var themeManager

    @State private var expanded: Set<URL> = []
    @State private var renameTarget: URL?
    @State private var renameText: String = ""
    @State private var deleteConfirm = false

    var body: some View {
        @Bindable var tree = env.fileTree
        let theme = themeManager.theme

        treeContent(tree: tree, theme: theme)
            .task(id: env.vault.current?.root) { await env.fileTree.refresh() }
            .onReceive(NotificationCenter.default.publisher(for: .lumenCollapseAllFolders)) { _ in
                expanded.removeAll()
            }
            .alert("Rename", isPresented: renamePresented) {
                TextField("Name", text: $renameText)
                Button("Cancel", role: .cancel) { renameTarget = nil }
                Button("Rename") {
                    Task {
                        await env.fileTree.rename(to: renameText); renameTarget = nil
                    }
                }
            }
            .alert("Move to Trash?", isPresented: $deleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Move to Trash", role: .destructive) {
                    Task { await env.fileTree.delete() }
                }
            } message: {
                Text(
                    "\(env.fileTree.selectedItem?.name ?? "This item") will be moved to the Trash.")
            }
    }

    // MARK: - Tree

    @ViewBuilder
    private func treeContent(tree: FileTreeModel, theme: Theme) -> some View {
        if env.vault.current == nil {
            placeholder("Open a vault to begin", icon: "folder.badge.plus", theme: theme)
        } else if tree.items.isEmpty {
            placeholder("No files yet", icon: "tray", theme: theme)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    TreeRows(
                        items: tree.items,
                        level: 0,
                        theme: theme,
                        expanded: $expanded,
                        selection: tree.selection,
                        onTap: { handleTap($0, tree: tree) },
                        contextMenu: { AnyView(contextMenu(for: $0)) }
                    )
                }
                .padding(.vertical, Spacing.xs)
                .padding(.horizontal, Spacing.sm)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func placeholder(_ text: String, icon: String, theme: Theme) -> some View {
        VStack {
            Spacer()
            Label(text, systemImage: icon)
                .font(Typography.font(.callout))
                .foregroundStyle(theme.color(.textSecondary))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Interaction

    private func handleTap(_ item: VaultItem, tree: FileTreeModel) {
        tree.selection = item.url
        if item.isDirectory {
            if expanded.contains(item.url) {
                expanded.remove(item.url)
            } else {
                expanded.insert(item.url)
            }
        } else if item.kind == .markdown {
            Task { await env.tabs.open(item.url) }
        }
    }

    // MARK: - Context menu

    @ViewBuilder
    private func contextMenu(for item: VaultItem) -> some View {
        // Right-click targets the clicked item for subsequent file ops.
        let select = { env.fileTree.selection = item.url }
        Button("New Note") {
            select(); Task { await env.fileTree.newNote() }
        }
        Button("New Folder") {
            select(); Task { await env.fileTree.newFolder() }
        }
        Divider()
        Button("Rename…") {
            select()
            renameText = item.name
            renameTarget = item.url
        }
        Button("Move to Trash", role: .destructive) {
            select(); deleteConfirm = true
        }
        Divider()
        Button("Reveal in Finder") {
            select(); env.fileTree.revealInFinder()
        }
    }

    // MARK: - Helpers

    private var renamePresented: Binding<Bool> {
        Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })
    }
}

/// Recursively renders a level of the tree, descending into expanded folders.
/// A dedicated view struct (rather than a recursive function returning
/// `some View`) so the opaque return type doesn't reference itself.
private struct TreeRows: View {
    let items: [VaultItem]
    let level: Int
    let theme: Theme
    @Binding var expanded: Set<URL>
    let selection: URL?
    let onTap: (VaultItem) -> Void
    let contextMenu: (VaultItem) -> AnyView

    var body: some View {
        ForEach(items) { item in
            FileRow(
                item: item,
                level: level,
                isSelected: selection == item.url,
                isExpanded: expanded.contains(item.url),
                theme: theme,
                onTap: { onTap(item) }
            )
            .contextMenu { contextMenu(item) }

            if item.isDirectory, expanded.contains(item.url) {
                TreeRows(
                    items: item.children,
                    level: level + 1,
                    theme: theme,
                    expanded: $expanded,
                    selection: selection,
                    onTap: onTap,
                    contextMenu: contextMenu
                )
            }
        }
    }
}

/// A single tree row: optional disclosure chevron + icon + name, indented by
/// depth. Folders use muted text; attachments are greyed/disabled. Hover and
/// active states use the neutral washes with a `Radius.small` rounded fill
/// (never the accent).
private struct FileRow: View {
    let item: VaultItem
    let level: Int
    let isSelected: Bool
    let isExpanded: Bool
    let theme: Theme
    let onTap: () -> Void
    @State private var isHovering = false

    private var indent: CGFloat { CGFloat(level) * 17 + Spacing.sm }

    private var rowBackground: Color {
        if isSelected { return theme.color(.activeWash) }
        if isHovering { return theme.color(.hoverWash) }
        return .clear
    }

    var body: some View {
        HStack(spacing: Spacing.xs) {
            if item.isDirectory {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(theme.color(.textPlaceholder))
                    .frame(width: 12)
            } else {
                Color.clear.frame(width: 12)
            }
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(iconColor)
            Text(item.name)
                .font(.system(size: 13))
                .foregroundStyle(textColor)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.leading, indent)
        .padding(.trailing, Spacing.sm)
        .frame(height: 26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.small).fill(rowBackground)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onHover { isHovering = $0 }
        .disabled(item.kind == .other)
        // UI test hook: address rows by name (e.g. "file-row-Welcome.md").
        .accessibilityIdentifier("file-row-\(item.name)")
    }

    private var textColor: Color {
        switch item.kind {
        case .other: theme.color(.textPlaceholder)
        case .folder: theme.color(.textSecondary)
        case .markdown: theme.color(.textPrimary)
        }
    }

    private var iconColor: Color {
        item.kind == .other ? theme.color(.textPlaceholder) : theme.color(.textSecondary)
    }

    private var symbol: String {
        switch item.kind {
        case .folder: "folder"
        case .markdown: "doc.text"
        case .other: "doc"
        }
    }
}
