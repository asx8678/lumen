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
//  width. Chrome surfaces are flat SOLID token fills (Obsidian-style, de-glassed
//  in lumen-p2b): tab bar + status bar = `windowBackground`, sidebar =
//  `sidebarBackground` (translucency defeated), editor = `editorBackground`.
//  Colors/type/spacing come from the LumenDesignSystem tokens.
//

import AppKit
import LumenCore
import LumenDesignSystem
import LumenEditor
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.scenePhase) private var scenePhase
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        let theme = themeManager.theme
        // Obsidian-style left ribbon: a fixed 44px column to the LEFT of the
        // NavigationSplitView sidebar. NavigationSplitView has no leading 3rd
        // column, so we wrap the whole shell in an HStack (lumen-df8).
        return HStack(spacing: 0) {
            RibbonView(
                sidebarVisible: columnVisibility != .detailOnly,
                toggleSidebar: toggleSidebar
            )
            NavigationSplitView(columnVisibility: $columnVisibility) {
                SidebarView()
                    .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 380)
            } detail: {
                EditorRegion(active: env.tabs.active, theme: theme)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        TabStripView(requestClose: requestClose)
                    }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                StatusBarView()
            }
        }
        .frame(minWidth: 720, minHeight: 460)
        .task(id: env.vault.current?.root) {
            env.reloadVaultSettings()
            await env.tabs.restore()
        }
        .task(id: env.vault.current?.root) {
            // Watch the vault and reconcile external edits against open tabs.
            guard let changes = env.startWatching() else { return }
            for await batch in changes {
                await env.tabs.reconcileExternalChanges(batch)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .lumenCloseActiveTab)) { _ in
            if let id = env.tabs.active?.id { requestClose(id) }
        }
        .onChange(of: scenePhase) { _, phase in
            // Flush pending autosave when the app loses focus / backgrounds.
            if phase != .active { Task { await env.tabs.flush() } }
        }
        .alert(
            "File Changed on Disk",
            isPresented: conflictPresented,
            presenting: env.tabs.active
        ) { document in
            Button("Keep My Version") { document.dismissConflict() }
            Button("Reload from Disk", role: .destructive) {
                Task { await document.reloadFromDisk() }
            }
        } message: { document in
            Text(
                "\(document.url?.lastPathComponent ?? "This file") was modified by another app "
                    + "while you have unsaved changes. Keep your version (then ⌘S to overwrite) "
                    + "or reload the on-disk version and lose your edits.")
        }
    }

    /// Whether the active tab has an unresolved external-edit conflict (P1.6).
    private var conflictPresented: Binding<Bool> {
        Binding(
            get: { env.tabs.active?.hasExternalConflict ?? false },
            set: { newValue in
                if !newValue { env.tabs.active?.dismissConflict() }
            })
    }

    /// Closes a tab, flushing/saving any unsaved changes first (autosave means
    /// no prompt is needed for normal closes — P1.11).
    private func requestClose(_ id: DocumentSession.ID) {
        Task { await env.tabs.saveAndClose(id: id) }
    }

    /// Toggles the left sidebar, mirroring the View ▸ Toggle Sidebar command.
    /// Driven by the ribbon's Files item.
    private func toggleSidebar() {
        columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
    }
}

// MARK: - Center editor region

/// The center region: the active tab's TextKit 2 editor on a token-colored
/// canvas. Shows an empty-state hint when no tab is open. Identified by the
/// active document's id so switching tabs swaps editor state cleanly.
private struct EditorRegion: View {
    @Environment(AppEnvironment.self) private var env
    let active: DocumentSession?
    let theme: Theme

    var body: some View {
        ZStack {
            theme.color(.editorBackground)
            if let active {
                ActiveEditor(document: active, theme: theme)
                    .id(active.id)
            } else if env.vault.current == nil {
                NoVaultView()
            } else {
                NoNoteSelectedView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// First-run / no-vault empty state: a prominent, actionable call to action that
/// reuses the same Open Vault… panel as File ▸ Open Vault… (⇧⌘O).
private struct NoVaultView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        ContentUnavailableView {
            Label("No Vault Open", systemImage: "folder.badge.plus")
        } description: {
            Text(
                "Open a folder to use as your Lumen vault. Your notes stay as plain "
                    + "Markdown files on disk.")
        } actions: {
            Button("Open Vault…") {
                presentOpenVaultPanel(into: env.vault)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("o", modifiers: [.command, .shift])
        }
    }
}

/// Vault-open-but-no-note empty state: a matching styled prompt that reuses the
/// existing new-note action (also bound to File ▸ New Note / ⌘N).
private struct NoNoteSelectedView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        ContentUnavailableView {
            Label("No Note Selected", systemImage: "doc.text")
        } description: {
            Text("Select a note from the sidebar, or create a new one to start writing.")
        } actions: {
            Button("New Note") {
                Task { await env.fileTree.newNote() }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

/// Binds the editor to a single document session, scheduling debounced autosave
/// on edits and flushing on blur (P1.11).
private struct ActiveEditor: View {
    @Environment(AppEnvironment.self) private var env
    @Bindable var document: DocumentSession
    let theme: Theme

    var body: some View {
        let typography = env.editorTypography.typography
        switch document.viewMode {
        case .source, .livePreview:
            TextKit2EditorView(
                text: $document.text,
                highlightTheme: MarkdownHighlightTheme(theme: theme, typography: typography),
                typography: typography,
                enableLivePreview: document.viewMode == .livePreview,
                noteBaseURL: document.url?.deletingLastPathComponent(),
                onOpenWikilink: { target in env.openWikilink(target) },
                onBlur: { Task { await env.tabs.flush() } }
            )
            .onChange(of: document.text) { _, _ in
                env.tabs.noteActiveEdited()
            }
        case .reading:
            ReadingPane(document: document, theme: theme, typography: typography)
        }
    }
}

/// The reading-mode pane: parses the active document's Markdown into a block
/// tree (off the typing hot path, recomputed when the text changes) and renders
/// it read-only via `MarkdownReadingView`.
private struct ReadingPane: View {
    let document: DocumentSession
    let theme: Theme
    let typography: EditorTypography
    @State private var blocks: [MarkdownBlock] = []
    @State private var parseTask: Task<Void, Never>?

    var body: some View {
        MarkdownReadingView(
            blocks: blocks,
            theme: theme,
            baseFontSize: typography.fontSize,
            maxContentWidth: typography.lineWidth.points,
            baseURL: document.url?.deletingLastPathComponent()
        )
        .task(id: document.text) { reparse(document.text) }
    }

    /// Debounces parsing so a note that's edited then read doesn't reparse on
    /// every keystroke; the reading view itself is read-only.
    private func reparse(_ text: String) {
        blocks = MarkdownDocumentParser.parseBlocks(text)
    }
}

// MARK: - Tab strip (Obsidian-style, de-glassed — P2 lumen-p2b)

/// The tab strip: flat rectangular tabs on a solid `windowBackground` bar. The
/// active tab uses `editorBackground` with rounded TOP corners so it visually
/// fuses into the editor below; inactive tabs carry a 1px bottom separator.
/// A trailing "+" reuses the New Note action; the ViewModePicker stays pinned
/// to the right.
private struct TabStripView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(ThemeManager.self) private var themeManager
    let requestClose: (DocumentSession.ID) -> Void

    var body: some View {
        let theme = themeManager.theme
        return HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(env.tabs.tabs) { tab in
                        TabPill(
                            tab: tab,
                            isActive: tab.id == env.tabs.activeID,
                            theme: theme,
                            onSelect: { env.tabs.activate(tab.id) },
                            onClose: { requestClose(tab.id) }
                        )
                        .draggable(TabDragID(id: tab.id)) {
                            Text(tab.url?.lastPathComponent ?? "Untitled")
                                .padding(Spacing.xs)
                        }
                        .dropDestination(for: TabDragID.self) { items, _ in
                            guard let dragged = items.first else { return false }
                            moveTab(dragged.id, before: tab.id)
                            return true
                        }
                    }

                    NewTabButton(theme: theme) {
                        Task { await env.fileTree.newNote() }
                    }
                    .disabled(env.vault.current == nil)
                }
            }

            Spacer(minLength: 0)

            if env.tabs.active != nil {
                ViewModePicker()
                    .padding(.horizontal, Spacing.sm)
            }
        }
        .frame(height: 40)
        .frame(maxWidth: .infinity)
        .background(theme.color(.windowBackground))
        .overlay(alignment: .bottom) {
            // Hairline under the whole bar; the active tab paints over it.
            theme.color(.separator).frame(height: 1)
        }
    }

    private func moveTab(_ dragged: DocumentSession.ID, before target: DocumentSession.ID) {
        guard dragged != target,
            let from = env.tabs.tabs.firstIndex(where: { $0.id == dragged }),
            let to = env.tabs.tabs.firstIndex(where: { $0.id == target })
        else { return }
        env.tabs.move(
            fromOffsets: IndexSet(integer: from),
            toOffset: to > from ? to + 1 : to)
    }
}

/// The trailing "+" new-tab affordance.
private struct NewTabButton: View {
    let theme: Theme
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.color(.textSecondary))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: Radius.small)
                        .fill(isHovering ? theme.color(.hoverWash) : .clear)
                )
                .padding(.horizontal, Spacing.xs)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("New tab")
    }
}

/// A compact 3-way segmented control: switches the active tab between Source,
/// Live Preview, and Reading modes (P2.2.1g). Mirrors the View-menu commands.
private struct ViewModePicker: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Picker("View Mode", selection: modeBinding) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .tag(EditorViewMode.source)
                .help("Source")
            Image(systemName: "eye")
                .tag(EditorViewMode.livePreview)
                .help("Live Preview")
            Image(systemName: "book")
                .tag(EditorViewMode.reading)
                .help("Reading view (⌘E)")
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }

    private var modeBinding: Binding<EditorViewMode> {
        Binding(
            get: { env.tabs.active?.viewMode ?? .source },
            set: { newValue in env.tabs.setActiveViewMode(newValue) })
    }
}

/// A single flat tab. Inactive: `windowBackground` + muted text + 1px bottom
/// separator. Active: `editorBackground` + primary text, top corners rounded
/// (`Radius.medium`) and NO bottom border so it fuses into the editor. The
/// leading glyph is a dirty dot, swapped to a close × on hover.
private struct TabPill: View {
    let tab: DocumentSession
    let isActive: Bool
    let theme: Theme
    let onSelect: () -> Void
    let onClose: () -> Void
    @State private var isHovering = false

    private var background: Color {
        theme.color(isActive ? .editorBackground : .windowBackground)
    }

    var body: some View {
        HStack(spacing: Spacing.xs) {
            leadingGlyph
                .frame(width: 14, height: 14)
            Text(tab.url?.lastPathComponent ?? "Untitled")
                .font(Typography.font(.body))
                .lineLimit(1)
        }
        .foregroundStyle(isActive ? theme.color(.textPrimary) : theme.color(.textSecondary))
        .padding(.horizontal, Spacing.md)
        .frame(maxHeight: .infinity)
        .frame(minWidth: 96, maxWidth: 200)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: Radius.medium,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: Radius.medium
            )
            .fill(background)
        )
        .overlay(alignment: .bottom) {
            // Inactive tabs keep the bar's hairline; the active tab covers it.
            if !isActive {
                theme.color(.separator).frame(height: 1)
            }
        }
        .overlay(alignment: .trailing) {
            // 1px divider between adjacent inactive tabs.
            if !isActive {
                theme.color(.separator).frame(width: 1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
    }

    @ViewBuilder
    private var leadingGlyph: some View {
        if isHovering {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(theme.color(.textSecondary))
            }
            .buttonStyle(.plain)
            .help("Close tab (⌘W)")
        } else if tab.isDirty {
            Circle()
                .fill(theme.accentColor)
                .frame(width: 7, height: 7)
        } else {
            Image(systemName: "doc.text")
                .font(.system(size: 11))
        }
    }
}

/// Transferable id used for drag-to-reorder.
private struct TabDragID: Transferable, Codable {
    let id: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
    }
}

// MARK: - Sidebar (Obsidian-style: header action row + tree + vault cluster)

/// Left sidebar: a compact header action row over the file tree, with a vault
/// status cluster pinned to the bottom. The surface is a SOLID
/// `sidebarBackground` — the NavigationSplitView sidebar is natively
/// translucent, so we both defeat its NSVisualEffectView material
/// (`SidebarSolidBackground`) and paint an opaque token fill on top.
private struct SidebarView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        let theme = themeManager.theme
        return VStack(alignment: .leading, spacing: 0) {
            // No hard rule under the header row (Obsidian relies on elevation).
            SidebarHeaderRow()
            FileTreeView()
            // Single precise 1px hairline above the bottom vault cluster.
            theme.color(.separator).frame(height: 1)
            VaultStatusCluster(vault: env.vault.current)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SidebarSolidBackground())
        .background(theme.color(.sidebarBackground))
        .navigationTitle(env.vault.current?.name ?? "Lumen")
    }
}

/// Compact header action row: thin muted icon buttons wired to the existing
/// file-tree actions.
private struct SidebarHeaderRow: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        let theme = themeManager.theme
        @Bindable var tree = env.fileTree
        let disabled = env.vault.current == nil
        return HStack(spacing: Spacing.xs) {
            SidebarIconButton(systemName: "square.and.pencil", help: "New note") {
                Task { await env.fileTree.newNote() }
            }
            SidebarIconButton(systemName: "folder.badge.plus", help: "New folder") {
                Task { await env.fileTree.newFolder() }
            }
            Menu {
                Picker("Sort", selection: $tree.sortOrder) {
                    Text("Name").tag(VaultSortOrder.name)
                    Text("Modified").tag(VaultSortOrder.modifiedDescending)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(theme.color(.textSecondary))
            // borderlessButton menus tint their label with the app accent;
            // override so the sort glyph stays neutral chrome.
            .tint(theme.color(.textSecondary))
            .help("Sort")

            Spacer()

            SidebarIconButton(systemName: "chevron.up.chevron.down", help: "Collapse all") {
                NotificationCenter.default.post(name: .lumenCollapseAllFolders, object: nil)
            }
        }
        .font(.system(size: 13))
        .disabled(disabled)
        .padding(.horizontal, Spacing.md)
        .frame(height: 36)
    }
}

/// A thin, muted square icon button with a neutral hover wash.
private struct SidebarIconButton: View {
    @Environment(ThemeManager.self) private var themeManager
    let systemName: String
    let help: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        let theme = themeManager.theme
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13))
                .foregroundStyle(theme.color(.textSecondary))
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: Radius.small)
                        .fill(isHovering ? theme.color(.hoverWash) : .clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(help)
    }
}

/// Bottom vault status cluster: just the "{Vault} ⌄" switcher, matching
/// Obsidian's bottom-left vault control. Help + settings now live in the left
/// ribbon's bottom group (deduped in lumen-df8), so they're intentionally gone
/// from here.
private struct VaultStatusCluster: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(ThemeManager.self) private var themeManager
    let vault: Vault?

    var body: some View {
        let theme = themeManager.theme
        return HStack(spacing: Spacing.xs) {
            Menu {
                Button("Open Vault…") { presentOpenVaultPanel(into: env.vault) }
                if !env.vault.recents.isEmpty {
                    Divider()
                    ForEach(env.vault.recents) { recent in
                        Button(recent.name) { openRecentVault(recent, into: env.vault) }
                    }
                }
            } label: {
                HStack(spacing: Spacing.xxs) {
                    Text(vault?.name ?? "No Vault")
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9))
                }
                .foregroundStyle(theme.color(.textSecondary))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            // Keep the vault name/chevron muted, not accent-coral.
            .tint(theme.color(.textSecondary))
            .help("Switch vault")

            Spacer()
        }
        .font(.system(size: 12))
        .padding(.horizontal, Spacing.md)
        .frame(height: 32)
    }
}

/// Defeats the NavigationSplitView sidebar's native translucency by walking up
/// to the enclosing `NSVisualEffectView` and forcing an opaque, non-vibrant
/// state. An opaque token fill is layered on top in `SidebarView`, but this
/// stops the system material from bleeding through at the edges.
private struct SidebarSolidBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { SolidifierView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class SolidifierView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            solidifyEnclosingVisualEffect()
        }

        private func solidifyEnclosingVisualEffect() {
            var view: NSView? = superview
            while let current = view {
                if let effect = current as? NSVisualEffectView {
                    effect.state = .inactive
                    effect.material = .windowBackground
                    effect.isEmphasized = false
                }
                view = current.superview
            }
        }
    }
}

// MARK: - Status bar (P1.18: word/char count, save state, indexing)

/// Slim bottom status bar: live word/character count + save state (left) and a
/// subtle indexing indicator (right). Counts are recomputed off the typing hot
/// path (debounced) so large documents stay smooth.
private struct StatusBarView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(ThemeManager.self) private var themeManager
    @State private var metrics: TextMetrics = .empty
    @State private var recomputeTask: Task<Void, Never>?

    var body: some View {
        let theme = themeManager.theme
        let active = env.tabs.active
        return HStack(spacing: Spacing.sm) {
            if active != nil {
                SaveStateLabel(isDirty: active?.isDirty ?? false, theme: theme)
            } else {
                Text("No note")
                    .font(Typography.font(.callout))
                    .foregroundStyle(theme.color(.textPlaceholder))
            }

            IndexingIndicator(status: env.indexingStatus, theme: theme)

            Spacer()

            // Obsidian right-aligns word/char metrics in the status bar.
            if active != nil {
                Text(countLabel)
                    .font(Typography.font(.callout))
                    .foregroundStyle(theme.color(.textSecondary))
            }
        }
        .padding(.horizontal, Spacing.md)
        .frame(height: 24)
        .frame(maxWidth: .infinity)
        .background(theme.color(.windowBackground))
        .overlay(alignment: .top) { theme.color(.separator).frame(height: 1) }
        .task(id: active?.id) { recompute(active?.text ?? "") }
        .onChange(of: active?.text ?? "") { _, newText in
            scheduleRecompute(newText)
        }
    }

    private var countLabel: String {
        "\(metrics.words.formatted()) words · \(metrics.characters.formatted()) characters"
    }

    /// Debounces recomputation so each keystroke doesn't re-scan a large doc.
    private func scheduleRecompute(_ text: String) {
        recomputeTask?.cancel()
        recomputeTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            if Task.isCancelled { return }
            recompute(text)
        }
    }

    private func recompute(_ text: String) {
        metrics = TextMetrics(counting: text)
    }
}

/// Save-state chip: a subtle dot + label driven by the document's dirty flag.
private struct SaveStateLabel: View {
    let isDirty: Bool
    let theme: Theme

    var body: some View {
        let state = SaveState(isDirty: isDirty)
        HStack(spacing: Spacing.xs) {
            Circle()
                .fill(isDirty ? theme.accentColor : theme.color(.textPlaceholder))
                .frame(width: 6, height: 6)
            Text(state.label)
                .font(Typography.font(.callout))
                .foregroundStyle(theme.color(.textSecondary))
        }
    }
}

/// Understated indexing indicator: a small spinner + count while indexing.
private struct IndexingIndicator: View {
    let status: IndexingStatus
    let theme: Theme

    var body: some View {
        if status.isIndexing {
            HStack(spacing: Spacing.xs) {
                ProgressView()
                    .controlSize(.mini)
                Text("Indexing \(status.processed)/\(status.total)")
                    .font(Typography.font(.callout))
                    .foregroundStyle(theme.color(.textPlaceholder))
            }
            .transition(.opacity)
        }
    }
}

#Preview {
    let env = AppEnvironment(vault: VaultManager(reopenLast: false))
    return ContentView()
        .environment(env)
        .environment(env.theme)
}
