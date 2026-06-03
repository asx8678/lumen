//
//  ReconciliationTests.swift
//  LumenCoreTests
//
//  P1.6: external-change reconciliation decision + change coalescing +
//  self-write suppression via DocumentSession.reconcileExternalChange.
//

import Foundation
import XCTest

@testable import LumenCore

final class ReconciliationTests: XCTestCase {
    // MARK: - Pure decision

    func testIgnoreWhenDiskMatchesBaseline() {
        // Covers our own writes / echo events.
        XCTAssertEqual(
            FileReconciliation.decide(onDiskHash: "h", baselineHash: "h", isDirty: false),
            .ignore)
        XCTAssertEqual(
            FileReconciliation.decide(onDiskHash: "h", baselineHash: "h", isDirty: true),
            .ignore)
    }

    func testReloadWhenChangedAndClean() {
        XCTAssertEqual(
            FileReconciliation.decide(onDiskHash: "new", baselineHash: "old", isDirty: false),
            .reload)
    }

    func testWarnWhenChangedAndDirty() {
        XCTAssertEqual(
            FileReconciliation.decide(onDiskHash: "new", baselineHash: "old", isDirty: true),
            .warnConflict)
    }

    // MARK: - Coalescing

    @MainActor
    func testCoalescerEmitsSingleUnionedBatch() async {
        var batches: [Set<URL>] = []
        let coalescer = ChangeCoalescer(interval: .milliseconds(30)) { batches.append($0) }
        let a = URL(fileURLWithPath: "/v/a.md")
        let b = URL(fileURLWithPath: "/v/b.md")
        coalescer.record([a])
        coalescer.record([b, a])  // duplicate a coalesces
        try? await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(batches.count, 1)
        XCTAssertEqual(batches.first, [a, b])
    }

    @MainActor
    func testCoalescerFlushEmitsImmediately() {
        var batches: [Set<URL>] = []
        let coalescer = ChangeCoalescer(interval: .seconds(100)) { batches.append($0) }
        coalescer.record([URL(fileURLWithPath: "/v/a.md")])
        coalescer.flush()
        XCTAssertEqual(batches.count, 1)
    }

    @MainActor
    func testCoalescerIgnoresEmptyRecord() {
        var calls = 0
        let coalescer = ChangeCoalescer(interval: .seconds(100)) { _ in calls += 1 }
        coalescer.record([])
        coalescer.flush()
        XCTAssertEqual(calls, 0)
    }

    // MARK: - DocumentSession reconciliation (self-write suppression + reload)

    private func makeTempFile(_ contents: String) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LumenRecon-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("note.md")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @MainActor
    func testOwnWriteIsIgnored() async throws {
        let url = try makeTempFile("hello")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let session = DocumentSession(files: FileService())
        try await session.open(url)
        session.text = "hello edited"
        try await session.save()  // our write; disk now == savedText

        await session.reconcileExternalChange()
        XCTAssertFalse(session.hasExternalConflict)
        XCTAssertEqual(session.text, "hello edited")
    }

    @MainActor
    func testExternalChangeWhenCleanReloads() async throws {
        let url = try makeTempFile("v1")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let session = DocumentSession(files: FileService())
        try await session.open(url)
        XCTAssertFalse(session.isDirty)

        // Simulate an external editor changing the file.
        try "v2 external".write(to: url, atomically: true, encoding: .utf8)
        await session.reconcileExternalChange()

        XCTAssertEqual(session.text, "v2 external")
        XCTAssertFalse(session.isDirty)
        XCTAssertFalse(session.hasExternalConflict)
    }

    @MainActor
    func testExternalChangeWhenDirtyWarns() async throws {
        let url = try makeTempFile("v1")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let session = DocumentSession(files: FileService())
        try await session.open(url)
        session.text = "my local unsaved edits"  // dirty

        try "v2 external".write(to: url, atomically: true, encoding: .utf8)
        await session.reconcileExternalChange()

        XCTAssertTrue(session.hasExternalConflict)
        XCTAssertEqual(session.text, "my local unsaved edits")  // not clobbered

        // Resolving by reloading from disk discards local edits.
        await session.reloadFromDisk()
        XCTAssertEqual(session.text, "v2 external")
        XCTAssertFalse(session.hasExternalConflict)
    }
}
