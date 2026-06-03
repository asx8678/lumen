//
//  TabManager.swift
//  Lumen
//
//  The tabbed editor (P1.16): an ordered collection of open documents — each a
//  `DocumentSession` (P1.15) — with an active selection. Wraps DocumentSession's
//  load/save/dirty logic unchanged; adds open-or-focus, close + reselection,
//  reorder, and persist/restore (via LumenCore's TabSupport/TabStore).
//

import Foundation
import LumenCore
import Observation
import SwiftUI
import os

@MainActor
@Observable
final class TabManager {
    /// Open tabs in display order.
    private(set) var tabs: [DocumentSession] = []

    /// The active tab's id.
    var activeID: DocumentSession.ID? {
        didSet { persist() }
    }

    /// Switches the active tab, flushing the outgoing document's pending save
    /// first so edits are never lost when leaving a tab (P1.11).
    func activate(_ id: DocumentSession.ID) {
        guard id != activeID else { return }
        Task {
            await flush()
            activeID = id
        }
    }

    @ObservationIgnored private let files: FileService
    @ObservationIgnored private let vault: VaultManager
    @ObservationIgnored private let store: TabStore
    @ObservationIgnored private let logger = Logger(subsystem: "ai.Lumen", category: "Tabs")
    @ObservationIgnored private var autosave: AutosaveScheduler!

    init(vault: VaultManager, files: FileService, store: TabStore = TabStore()) {
        self.vault = vault
        self.files = files
        self.store = store
        self.autosave = AutosaveScheduler { [weak self] in
            await self?.saveActiveIfNeeded()
        }
    }

    // MARK: - Autosave (P1.11)

    /// Schedules a debounced autosave; call on each edit to the active document.
    func noteActiveEdited() {
        autosave.schedule()
    }

    /// Flushes any pending autosave immediately (blur / tab-switch / background
    /// / close). Safe to call when nothing is pending.
    func flush() async {
        await autosave.flush()
    }

    /// Reconciles a batch of externally-changed URLs against open tabs (P1.6):
    /// clean tabs reload, dirty tabs raise a conflict warning, our own writes
    /// are ignored (handled inside `DocumentSession.reconcileExternalChange`).
    func reconcileExternalChanges(_ urls: Set<URL>) async {
        let standardized = Set(urls.map { $0.standardizedFileURL })
        for tab in tabs {
            guard let tabURL = tab.url?.standardizedFileURL, standardized.contains(tabURL) else {
                continue
            }
            await tab.reconcileExternalChange()
        }
    }

    private func saveActiveIfNeeded() async {
        do { try await active?.autosaveIfNeeded() } catch {
            logger.error("Autosave failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// The active document, or `nil` when no tabs are open.
    var active: DocumentSession? {
        guard let activeID else { return nil }
        return tabs.first { $0.id == activeID }
    }

    // MARK: - Open

    /// Opens `url` in a new tab, or focuses the existing tab if already open.
    func open(_ url: URL) async {
        await flush()  // persist any pending edits before switching focus
        if let existing = tabs.first(where: { $0.url == url }) {
            activeID = existing.id
            return
        }
        let session = DocumentSession(files: files)
        do {
            try await session.open(url)
        } catch {
            logger.error("Open failed: \(String(describing: error), privacy: .public)")
            return
        }
        tabs.append(session)
        activeID = session.id  // triggers persist
    }

    // MARK: - Close

    /// Flushes any unsaved changes in a tab, then closes it. With autosave on,
    /// this means normal closes never lose edits and never need a prompt (P1.11).
    func saveAndClose(id: DocumentSession.ID) async {
        await flush()
        if let doc = tabs.first(where: { $0.id == id }), doc.isDirty {
            do { try await doc.save() } catch {
                logger.error("Save-on-close failed: \(String(describing: error), privacy: .public)")
            }
        }
        close(id: id)
    }

    /// Closes the tab with `id`, selecting an adjacent tab if it was active.
    func close(id: DocumentSession.ID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let wasActive = (id == activeID)
        let newActiveIndex = TabSupport.activeIndexAfterRemoving(index, count: tabs.count)
        tabs.remove(at: index)
        if wasActive {
            activeID = newActiveIndex.map { tabs[$0].id }  // triggers persist
        } else {
            persist()
        }
    }

    // MARK: - Reorder

    /// Reorders tabs (drag-and-drop in the strip).
    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        tabs.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    // MARK: - Save

    /// Saves the active tab.
    func saveActive() async {
        do { try await active?.save() } catch {
            logger.error("Save failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Persist / restore

    /// Persists the open tabs (relative paths + active index) for the vault.
    func persist() {
        guard let root = vault.current?.root else { return }
        let urls = tabs.compactMap(\.url)
        let relativePaths = urls.compactMap { TabSupport.relativePath(of: $0, root: root) }
        let activeIndex =
            active?.url
            .flatMap { url in urls.firstIndex(of: url) } ?? 0
        store.save(
            TabsSnapshot(relativePaths: relativePaths, activeIndex: activeIndex),
            vaultRoot: root)
    }

    /// Restores persisted tabs for the current vault (skips missing files).
    /// Call after the vault opens/changes; resets the current tab set first.
    func restore() async {
        tabs = []
        activeID = nil
        guard let root = vault.current?.root else { return }
        let snapshot = store.load(vaultRoot: root)
        let resolved = TabStore.resolve(snapshot, vaultRoot: root) {
            FileManager.default.fileExists(atPath: $0.path)
        }
        for url in resolved.urls {
            let session = DocumentSession(files: files)
            do {
                try await session.open(url)
                tabs.append(session)
            } catch {
                logger.error("Restore open failed: \(String(describing: error), privacy: .public)")
            }
        }
        if let index = resolved.activeIndex, tabs.indices.contains(index) {
            activeID = tabs[index].id
        }
    }
}
