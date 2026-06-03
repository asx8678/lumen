//
//  NotesIndexTests.swift
//  LumenCoreTests
//
//  P1.8: migration, NoteRecord round-trip (incl. serialized frontmatter),
//  CRUD, change detection, and `.lumen/index.sqlite` creation.
//

import Foundation
import XCTest

@testable import LumenCore

final class NotesIndexTests: XCTestCase {
    private func sampleRecord(path: String = "notes/a.md", hash: String = "h1") -> NoteRecord {
        let fm = Frontmatter(title: "A", tags: ["x", "y"], raw: ["custom": .int(3)])
        return NoteRecord(
            path: path,
            title: "A",
            mtime: 1000,
            size: 42,
            frontmatter: NoteRecord.encodeFrontmatter(fm),
            contentHash: hash)
    }

    // MARK: - Migration + round-trip

    func testMigrationAndRoundTrip() throws {
        let index = try NotesIndex()
        let record = sampleRecord()
        try index.upsert(record)

        let fetched = try index.record(forPath: record.path)
        XCTAssertEqual(fetched, record)

        // Serialized frontmatter survives the round-trip.
        let decoded = fetched?.decodedFrontmatter
        XCTAssertEqual(decoded?.title, "A")
        XCTAssertEqual(decoded?.tags, ["x", "y"])
        XCTAssertEqual(decoded?.raw["custom"], .int(3))
    }

    func testUpsertReplacesByPath() throws {
        let index = try NotesIndex()
        try index.upsert(sampleRecord(hash: "h1"))
        try index.upsert(sampleRecord(hash: "h2"))  // same path
        XCTAssertEqual(try index.count(), 1)
        XCTAssertEqual(try index.record(forPath: "notes/a.md")?.contentHash, "h2")
    }

    func testBatchUpsertAllRecordsAndPaths() throws {
        let index = try NotesIndex()
        try index.upsert([
            sampleRecord(path: "b.md"),
            sampleRecord(path: "a.md"),
        ])
        XCTAssertEqual(try index.allRecords().map(\.path), ["a.md", "b.md"])
        XCTAssertEqual(try index.allPaths(), ["a.md", "b.md"])
    }

    func testDelete() throws {
        let index = try NotesIndex()
        try index.upsert(sampleRecord())
        XCTAssertTrue(try index.deleteRecord(path: "notes/a.md"))
        XCTAssertNil(try index.record(forPath: "notes/a.md"))
        XCTAssertFalse(try index.deleteRecord(path: "notes/a.md"))
    }

    func testDeleteAll() throws {
        let index = try NotesIndex()
        try index.upsert([sampleRecord(path: "a.md"), sampleRecord(path: "b.md")])
        try index.deleteAll()
        XCTAssertEqual(try index.count(), 0)
    }

    // MARK: - Change detection

    func testNeedsReindexForNewFile() {
        XCTAssertTrue(
            NoteIndexing.needsReindex(existing: nil, mtime: 1, size: 1, hash: "h"))
    }

    func testNeedsReindexWhenHashChanges() {
        let existing = sampleRecord(hash: "old")
        XCTAssertTrue(
            NoteIndexing.needsReindex(existing: existing, mtime: 1000, size: 42, hash: "new"))
    }

    func testNoReindexWhenUnchanged() {
        let existing = sampleRecord(hash: "same")
        XCTAssertFalse(
            NoteIndexing.needsReindex(existing: existing, mtime: 1000, size: 42, hash: "same"))
    }

    func testNeedsReindexWhenSizeChanges() {
        let existing = sampleRecord(hash: "same")
        XCTAssertTrue(
            NoteIndexing.needsReindex(existing: existing, mtime: 1000, size: 99, hash: "same"))
    }

    func testNeedsReindexViaStore() throws {
        let index = try NotesIndex()
        try index.upsert(sampleRecord(hash: "h1"))
        XCTAssertFalse(
            try index.needsReindex(path: "notes/a.md", mtime: 1000, size: 42, hash: "h1"))
        XCTAssertTrue(try index.needsReindex(path: "notes/a.md", mtime: 1000, size: 42, hash: "h2"))
        XCTAssertTrue(try index.needsReindex(path: "missing.md", mtime: 1, size: 1, hash: "x"))
    }

    // MARK: - Record building

    func testMakeRecordUsesFrontmatterTitleThenFilename() {
        let withTitle = NoteIndexing.makeRecord(
            relativePath: "x/note.md", text: "body", mtime: 1, size: 4,
            parsed: ParsedNote(frontmatter: Frontmatter(title: "Real"), body: "body"))
        XCTAssertEqual(withTitle.title, "Real")

        let noTitle = NoteIndexing.makeRecord(
            relativePath: "x/note.md", text: "body", mtime: 1, size: 4,
            parsed: ParsedNote(frontmatter: nil, body: "body"))
        XCTAssertEqual(noTitle.title, "note")
        XCTAssertEqual(noTitle.contentHash, NoteIndexing.contentHash(of: "body"))
    }

    func testContentHashIsStableAndSensitive() {
        XCTAssertEqual(NoteIndexing.contentHash(of: "abc"), NoteIndexing.contentHash(of: "abc"))
        XCTAssertNotEqual(NoteIndexing.contentHash(of: "abc"), NoteIndexing.contentHash(of: "abd"))
    }

    // MARK: - On-disk DB creation

    func testCreatesDotLumenDatabaseFile() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LumenIndexTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let index = try NotesIndex(vaultRoot: root)
        try index.upsert(sampleRecord())

        let dbURL = root.appendingPathComponent(".lumen/index.sqlite")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dbURL.path))

        // A fresh handle on the same path sees the persisted row.
        let reopened = try NotesIndex(vaultRoot: root)
        XCTAssertEqual(try reopened.count(), 1)
    }
}
