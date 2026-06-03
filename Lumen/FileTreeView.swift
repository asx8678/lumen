//
//  FileTreeView.swift
//  Lumen
//
//  The sidebar file tree (P1.15): folders + .md files (attachments greyed),
//  expandable, sortable, with a right-click file-op context menu. Selecting a
//  Markdown file loads it into the editor via the open-document model.
//

import LumenCore
import LumenDesignSystem
import SwiftUI

struct FileTreeView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(ThemeManager.self) private var themeManager

    @State private var renameTarget: URL?
    @State private var renameText: String = ""
    @State private var deleteConfirm = false

    var body: some View {
        @Bindable var tree = env.fileTree
        let theme = themeManager.theme

        VStack(spacing: 0) {
            sortBar(theme: theme)
            Divider().overlay(theme.color(.separator))
            treeContent(tree: tree, theme: theme)
        }
        .task(id: env.vault.current?.root) { await env.fileTree.refresh() }
        .onChange(of: tree.selection) { _, newValue in
            openIfMarkdown(newValue)
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
            Text("\(env.fileTree.selectedItem?.name ?? "This item") will be moved to the Trash.")
        }
    }

    // MARK: - Sort bar

    private func sortBar(theme: Theme) -> some View {
        @Bindable var tree = env.fileTree
        return HStack(spacing: Spacing.sm) {
            Picker("Sort", selection: $tree.sortOrder) {
                Text("Name").tag(VaultSortOrder.name)
                Text("Modified").tag(VaultSortOrder.modifiedDescending)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .controlSize(.small)

            Spacer()

            Button {
                Task { await env.fileTree.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Refresh")
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
    }

    // MARK: - Tree

    @ViewBuilder
    private func treeContent(tree: FileTreeModel, theme: Theme) -> some View {
        if env.vault.current == nil {
            placeholder("Open a vault to begin", icon: "folder.badge.plus", theme: theme)
        } else if tree.items.isEmpty {
            placeholder("No files yet", icon: "tray", theme: theme)
        } else {
            List(selection: Bindable(tree).selection) {
                OutlineGroup(tree.items, children: \.childrenOrNil) { item in
                    FileRow(item: item, theme: theme)
                        .tag(item.url)
                        .contextMenu { contextMenu(for: item) }
                }
            }
            .listStyle(.sidebar)
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
        .frame(maxWidth: .infinity)
    }

    // MARK: - Context menu

    @ViewBuilder
    private func contextMenu(for item: VaultItem) -> some View {
        Button("New Note") { Task { await env.fileTree.newNote() } }
        Button("New Folder") { Task { await env.fileTree.newFolder() } }
        Divider()
        Button("Rename…") {
            renameText = item.name
            renameTarget = item.url
        }
        Button("Move to Trash", role: .destructive) { deleteConfirm = true }
        Divider()
        Button("Reveal in Finder") { env.fileTree.revealInFinder() }
    }

    // MARK: - Helpers

    private var renamePresented: Binding<Bool> {
        Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })
    }

    private func openIfMarkdown(_ url: URL?) {
        guard let url, env.fileTree.selectedItem?.kind == .markdown else { return }
        Task { await env.tabs.open(url) }
    }
}

/// A single row: icon + name; attachments are greyed/disabled.
private struct FileRow: View {
    let item: VaultItem
    let theme: Theme

    var body: some View {
        Label {
            Text(item.name)
                .font(Typography.font(.callout))
                .foregroundStyle(color)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(item.kind == .other ? theme.color(.textPlaceholder) : color)
        }
        .lineLimit(1)
        .disabled(item.kind == .other)
        // P1.21 UI test hook: address rows by name (e.g. "file-row-Welcome.md").
        .accessibilityIdentifier("file-row-\(item.name)")
    }

    private var color: Color {
        item.kind == .other ? theme.color(.textPlaceholder) : theme.color(.textPrimary)
    }

    private var symbol: String {
        switch item.kind {
        case .folder: "folder"
        case .markdown: "doc.text"
        case .other: "doc"
        }
    }
}

extension VaultItem {
    /// `children` for folders, or `nil` for leaves so `OutlineGroup` stops.
    fileprivate var childrenOrNil: [VaultItem]? {
        isDirectory ? children : nil
    }
}
