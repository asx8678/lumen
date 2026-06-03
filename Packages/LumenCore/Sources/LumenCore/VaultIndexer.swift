//
//  VaultIndexer.swift
//  LumenCore
//
//  The background indexing pipeline (P1.9). Runs OFF the main thread on an
//  `actor`, orchestrating the pieces already built:
//    enumerate (P1.5) → needsReindex (P1.8) → read + parse (P1.7) → upsert (P1.8)
//  plus deletion reconciliation, and incremental re-indexing from the FSEvents
//  watcher (P1.6). Progress is reported via `IndexingStatus` (main-actor).
//
//  The vault files are the source of truth; the index is a derived cache, so
//  any read/enumerate failure degrades quietly without corrupting user content.
//

import Foundation

/// Indexes a vault's Markdown files into a ``NotesIndex`` in the background.
public actor VaultIndexer {
    private let root: URL
    private let files: FileService
    private let index: NotesIndex
    private let status: IndexingStatus

    public init(root: URL, files: FileService, index: NotesIndex, status: IndexingStatus) {
        self.root = root
        self.files = files
        self.index = index
        self.status = status
    }

    /// Runs an initial full index, then re-indexes incrementally as the watcher
    /// reports changes. Returns when `events` finishes (watcher stopped).
    public func run(events: AsyncStream<Set<URL>>) async {
        await fullIndex()
        for await batch in events {
            await reindex(batch)
        }
    }

    // MARK: - Full index

    /// Enumerates the vault, (re)indexes changed/new `.md` files, and drops rows
    /// for files no longer present.
    public func fullIndex() async {
        let tree = (try? await files.enumerate(root)) ?? []
        let markdown = Self.markdownFiles(in: tree)

        await status.begin(total: markdown.count)

        var currentPaths = Set<String>()
        // Accumulate changed records and commit them in a SINGLE transaction at
        // the end (cold-index fast path) rather than one write per file.
        var pending: [NoteRecord] = []
        for item in markdown {
            guard let relativePath = TabSupport.relativePath(of: item.url, root: root) else {
                await status.advance()
                continue
            }
            currentPaths.insert(relativePath)
            if let record = await preparedRecordIfNeeded(
                url: item.url,
                relativePath: relativePath,
                mtime: item.modificationDate?.timeIntervalSince1970 ?? 0,
                size: Int64(item.size))
            {
                pending.append(record)
            }
            await status.advance()
        }

        if !pending.isEmpty {
            try? index.upsert(pending)
        }
        reconcileDeletions(currentPaths: currentPaths)
        await status.finish()
    }

    // MARK: - Incremental

    /// Re-indexes only the affected URLs (deleting rows for vanished files).
    public func reindex(_ urls: Set<URL>) async {
        let markdownURLs = urls.filter { Self.isMarkdown($0) }
        guard !markdownURLs.isEmpty else { return }

        await status.begin(total: markdownURLs.count)
        for url in markdownURLs {
            guard let relativePath = TabSupport.relativePath(of: url, root: root) else {
                await status.advance()
                continue
            }
            if let meta = fileMetadata(url) {
                if let record = await preparedRecordIfNeeded(
                    url: url, relativePath: relativePath, mtime: meta.mtime, size: meta.size)
                {
                    try? index.upsert(record)
                }
            } else {
                // File is gone — drop its derived row.
                _ = try? index.deleteRecord(path: relativePath)
            }
            await status.advance()
        }
        await status.finish()
    }

    // MARK: - Core upsert

    /// Builds the index record for one file if it changed versus the stored
    /// record, WITHOUT writing it. Returns `nil` when the file is unchanged or
    /// unreadable. Callers decide whether to write singly or batch the result.
    private func preparedRecordIfNeeded(
        url: URL, relativePath: String, mtime: Double, size: Int64
    ) async -> NoteRecord? {
        // Cheap skip: identical size + mtime ⇒ assume unchanged, avoid reading.
        if let existing = try? index.record(forPath: relativePath),
            existing.size == size, existing.mtime == mtime
        {
            return nil
        }
        guard let text = try? await files.read(url) else { return nil }
        let hash = NoteIndexing.contentHash(of: text)
        let needs =
            (try? index.needsReindex(path: relativePath, mtime: mtime, size: size, hash: hash))
            ?? true
        guard needs else { return nil }

        let parsed = FrontmatterParser.parse(text)
        return NoteIndexing.makeRecord(
            relativePath: relativePath, text: text, mtime: mtime, size: size, parsed: parsed)
    }

    /// Removes index rows whose files no longer exist in the enumeration.
    private func reconcileDeletions(currentPaths: Set<String>) {
        guard let indexed = try? index.allPaths() else { return }
        for stale in indexed.subtracting(currentPaths) {
            _ = try? index.deleteRecord(path: stale)
        }
    }

    // MARK: - Helpers

    /// Flattens a vault tree to its Markdown leaves (depth-first).
    static func markdownFiles(in items: [VaultItem]) -> [VaultItem] {
        var result: [VaultItem] = []
        for item in items {
            if item.isDirectory {
                result.append(contentsOf: markdownFiles(in: item.children))
            } else if item.kind == .markdown {
                result.append(item)
            }
        }
        return result
    }

    /// Whether a URL is a Markdown file by extension.
    static func isMarkdown(_ url: URL) -> Bool {
        ["md", "markdown"].contains(url.pathExtension.lowercased())
    }

    /// Reads `(mtime, size)` for an existing file, or `nil` if absent.
    private func fileMetadata(_ url: URL) -> (mtime: Double, size: Int64)? {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        guard let values, FileManager.default.fileExists(atPath: url.path) else { return nil }
        let mtime = values.contentModificationDate?.timeIntervalSince1970 ?? 0
        let size = Int64(values.fileSize ?? 0)
        return (mtime, size)
    }
}
