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
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.scenePhase) private var scenePhase
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        let theme = themeManager.theme
        return NavigationSplitView(columnVisibility: $columnVisibility) {
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

// MARK: - Tab strip (visual scaffold only — functional tabs are P1.16)

/// The real tab strip (P1.16): one Liquid Glass pill per open tab with a dirty
/// indicator, click-to-switch, close (×), drag-to-reorder, and a "+" affordance.
private struct TabStripView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(ThemeManager.self) private var themeManager
    let requestClose: (DocumentSession.ID) -> Void
    @Namespace private var glassNamespace

    var body: some View {
        let theme = themeManager.theme
        return GlassEffectContainer {
            HStack(spacing: Spacing.sm) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.sm) {
                        ForEach(env.tabs.tabs) { tab in
                            TabPill(
                                tab: tab,
                                isActive: tab.id == env.tabs.activeID,
                                theme: theme,
                                onSelect: { env.tabs.activate(tab.id) },
                                onClose: { requestClose(tab.id) }
                            )
                            .glassEffectID(tab.id, in: glassNamespace)
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
                    }
                    .padding(.vertical, Spacing.xs)
                }

                if env.tabs.active != nil {
                    ViewModePicker()
                }
            }
            .padding(.horizontal, Spacing.sm)
        }
        .frame(height: 36)
        .frame(maxWidth: .infinity)
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

/// A single tab pill.
private struct TabPill: View {
    let tab: DocumentSession
    let isActive: Bool
    let theme: Theme
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: Spacing.xs) {
            if tab.isDirty {
                Circle()
                    .fill(theme.accentColor)
                    .frame(width: 6, height: 6)
            } else {
                Image(systemName: "doc.text")
                    .font(.system(size: 11))
            }
            Text(tab.url?.lastPathComponent ?? "Untitled")
                .font(Typography.font(.callout))
                .lineLimit(1)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
            .help("Close tab (⌘W)")
        }
        .foregroundStyle(isActive ? theme.color(.textPrimary) : theme.color(.textSecondary))
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .glassChrome(in: .capsule)
        .overlay(
            Capsule().stroke(theme.accentColor.opacity(isActive ? 0.6 : 0), lineWidth: 1)
        )
        .contentShape(Capsule())
        .onTapGesture(perform: onSelect)
    }
}

/// Transferable id used for drag-to-reorder.
private struct TabDragID: Transferable, Codable {
    let id: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
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

            FileTreeView()

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The NavigationSplitView sidebar is already a native translucent
        // (Liquid Glass) surface; we layer token-colored content on top.
        .navigationTitle(env.vault.current?.name ?? "Lumen")
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
                Text("·").foregroundStyle(theme.color(.textPlaceholder))
                Text(countLabel)
                    .font(Typography.font(.caption))
                    .foregroundStyle(theme.color(.textSecondary))
            } else {
                Text("No note")
                    .font(Typography.font(.caption))
                    .foregroundStyle(theme.color(.textPlaceholder))
            }

            Spacer()

            IndexingIndicator(status: env.indexingStatus, theme: theme)
        }
        .padding(.horizontal, Spacing.md)
        .frame(height: 26)
        .frame(maxWidth: .infinity)
        .glassChrome(in: .rect)
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
                .font(Typography.font(.caption))
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
                    .font(Typography.font(.caption))
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
