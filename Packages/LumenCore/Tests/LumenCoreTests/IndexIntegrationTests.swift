//
//  IndexIntegrationTests.swift
//  LumenCoreTests
//
//  P1.20 sweep — cross-component flow: FileService enumerate/read +
//  FrontmatterParser + NoteIndexing + NotesIndex driven by VaultIndexer.
//  Index a temp vault, assert `notes` rows + stored frontmatter JSON, mutate a
//  file → only it reindexes, delete a file → its row is removed.
//

import Foundation
import XCTest

@testable import LumenCore

@MainActor
final class IndexIntegrationTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LumenIndexIntegration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    private func write(_ rel: String, _ contents: String) throws {
        let url = root.appendingPathComponent(rel)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func makeIndexer() throws -> (VaultIndexer, NotesIndex) {
        let index = try NotesIndex(vaultRoot: root)
        let indexer = VaultIndexer(
            root: root, files: FileService(), index: index, status: IndexingStatus())
        return (indexer, index)
    }

    func testFullFlowIndexesRowsAndFrontmatterJSON() async throws {
        try write(
            "alpha.md",
            """
            ---
            title: Alpha Note
            tags: [a, b]
            ---
            Hello world
            """)
        try write("sub/beta.md", "# Just a heading")

        let (indexer, index) = try makeIndexer()
        await indexer.fullIndex()

        XCTAssertEqual(try index.allPaths(), ["alpha.md", "sub/beta.md"])

        let alpha = try XCTUnwrap(try index.record(forPath: "alpha.md"))
        XCTAssertEqual(alpha.title, "Alpha Note")
        // Stored frontmatter is JSON and survives a decode round-trip.
        let decoded = try XCTUnwrap(alpha.decodedFrontmatter)
        XCTAssertEqual(decoded.title, "Alpha Note")
        XCTAssertEqual(decoded.tags, ["a", "b"])
        XCTAssertFalse(alpha.contentHash.isEmpty)

        // No-frontmatter note falls back to the filename stem for its title.
        let beta = try XCTUnwrap(try index.record(forPath: "sub/beta.md"))
        XCTAssertEqual(beta.title, "beta")
    }

    func testMutatingOneFileReindexesOnlyIt() async throws {
        try write("a.md", "one")
        try write("b.md", "two")
        let (indexer, index) = try makeIndexer()
        await indexer.fullIndex()

        let aHash1 = try XCTUnwrap(index.record(forPath: "a.md")).contentHash
        let bHash1 = try XCTUnwrap(index.record(forPath: "b.md")).contentHash

        // Edit a.md, bump mtime so the cheap gate re-reads it.
        try write("a.md", "one changed")
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(10)],
            ofItemAtPath: root.appendingPathComponent("a.md").path)

        await indexer.reindex([root.appendingPathComponent("a.md")])

        XCTAssertNotEqual(try XCTUnwrap(index.record(forPath: "a.md")).contentHash, aHash1)
        XCTAssertEqual(try XCTUnwrap(index.record(forPath: "b.md")).contentHash, bHash1)
    }

    func testDeletingFileRemovesRowViaFullIndexAndIncremental() async throws {
        try write("keep.md", "k")
        try write("gone.md", "g")
        let (indexer, index) = try makeIndexer()
        await indexer.fullIndex()
        XCTAssertEqual(try index.count(), 2)

        // Incremental: file vanished → row dropped.
        try FileManager.default.removeItem(at: root.appendingPathComponent("gone.md"))
        await indexer.reindex([root.appendingPathComponent("gone.md")])
        XCTAssertNil(try index.record(forPath: "gone.md"))
        XCTAssertEqual(try index.allPaths(), ["keep.md"])

        // Full index reconcile: a row with no on-disk file is also dropped.
        try index.upsert(
            NoteRecord(
                path: "phantom.md", title: "x", mtime: 0, size: 1, frontmatter: nil,
                contentHash: "deadbeef"))
        XCTAssertEqual(try index.count(), 2)
        await indexer.fullIndex()
        XCTAssertEqual(try index.allPaths(), ["keep.md"])
    }
}
