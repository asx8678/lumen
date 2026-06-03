//
//  VaultIndexerTests.swift
//  LumenCoreTests
//
//  P1.9: full index populates `notes`; re-index skips unchanged + picks up
//  new/changed; deletions are reconciled; progress counts are sane.
//  (The raw FSEvents-driven path is integration-only and not covered here.)
//

import Foundation
import XCTest

@testable import LumenCore

@MainActor
final class VaultIndexerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LumenIndexer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    private func write(_ relativePath: String, _ contents: String) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func makeIndexer() throws -> (VaultIndexer, NotesIndex, IndexingStatus) {
        let index = try NotesIndex(vaultRoot: root)
        let status = IndexingStatus()
        let indexer = VaultIndexer(
            root: root, files: FileService(), index: index, status: status)
        return (indexer, index, status)
    }

    // MARK: - Full index

    func testFullIndexPopulatesNotes() async throws {
        try write("a.md", "---\ntitle: Alpha\n---\nbody")
        try write("sub/b.md", "# Beta")
        try write("image.png", "not markdown")  // ignored

        let (indexer, index, status) = try await makeIndexer()
        await indexer.fullIndex()

        let paths = try index.allPaths()
        XCTAssertEqual(paths, ["a.md", "sub/b.md"])
        XCTAssertEqual(try index.record(forPath: "a.md")?.title, "Alpha")
        XCTAssertEqual(try index.record(forPath: "sub/b.md")?.title, "b")  // filename stem

        XCTAssertFalse(status.isIndexing)
        XCTAssertEqual(status.processed, 2)
    }

    func testSecondPassSkipsUnchangedAndPicksUpChanges() async throws {
        try write("a.md", "v1")
        try write("b.md", "stable")
        let (indexer, index, _) = try await makeIndexer()
        await indexer.fullIndex()

        let hashB1 = try index.record(forPath: "b.md")?.contentHash
        let hashA1 = try index.record(forPath: "a.md")?.contentHash

        // Change only a.md (touch mtime forward so the cheap gate re-reads).
        try write("a.md", "v2 changed")
        let url = root.appendingPathComponent("a.md")
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: url.path)

        await indexer.fullIndex()

        XCTAssertNotEqual(try index.record(forPath: "a.md")?.contentHash, hashA1)
        XCTAssertEqual(try index.record(forPath: "b.md")?.contentHash, hashB1)  // untouched
    }

    func testFullIndexReconcilesDeletions() async throws {
        try write("keep.md", "k")
        try write("gone.md", "g")
        let (indexer, index, _) = try await makeIndexer()
        await indexer.fullIndex()
        XCTAssertEqual(try index.count(), 2)

        try FileManager.default.removeItem(at: root.appendingPathComponent("gone.md"))
        await indexer.fullIndex()

        XCTAssertEqual(try index.allPaths(), ["keep.md"])
    }

    // MARK: - Incremental

    func testReindexAddsChangedAndRemovesDeleted() async throws {
        try write("a.md", "a")
        let (indexer, index, _) = try await makeIndexer()
        await indexer.fullIndex()
        XCTAssertEqual(try index.count(), 1)

        // New file appears + a.md deleted; reindex just those URLs.
        try write("new.md", "fresh")
        try FileManager.default.removeItem(at: root.appendingPathComponent("a.md"))
        await indexer.reindex([
            root.appendingPathComponent("new.md"),
            root.appendingPathComponent("a.md"),
        ])

        XCTAssertEqual(try index.allPaths(), ["new.md"])
        XCTAssertEqual(try index.record(forPath: "new.md")?.title, "new")
    }

    func testReindexIgnoresNonMarkdown() async throws {
        let (indexer, index, _) = try await makeIndexer()
        try write("note.txt", "text")
        await indexer.reindex([root.appendingPathComponent("note.txt")])
        XCTAssertEqual(try index.count(), 0)
    }

    // MARK: - Helpers

    func testMarkdownFilesFlattening() {
        let tree = [
            VaultItem(url: URL(fileURLWithPath: "/v/a.md"), kind: .markdown),
            VaultItem(
                url: URL(fileURLWithPath: "/v/sub"), kind: .folder,
                children: [
                    VaultItem(url: URL(fileURLWithPath: "/v/sub/b.md"), kind: .markdown),
                    VaultItem(url: URL(fileURLWithPath: "/v/sub/c.png"), kind: .other),
                ]),
        ]
        let md = VaultIndexer.markdownFiles(in: tree).map(\.url.lastPathComponent)
        XCTAssertEqual(md, ["a.md", "b.md"])
    }
}
