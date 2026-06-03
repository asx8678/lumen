//
//  AutosaveTests.swift
//  LumenCoreTests
//
//  P1.11: debounce coalescing, immediate flush, and dirty-guarded autosave.
//

import Foundation
import XCTest

@testable import LumenCore

@MainActor
final class AutosaveTests: XCTestCase {
    /// Counts how many times the action ran.
    private final class Counter {
        var count = 0
    }

    func testFlushRunsImmediatelyEvenWithLongInterval() async {
        let counter = Counter()
        let scheduler = AutosaveScheduler(interval: .seconds(100)) {
            counter.count += 1
        }
        scheduler.schedule()  // would not fire for 100s
        await scheduler.flush()
        XCTAssertEqual(counter.count, 1)
        XCTAssertFalse(scheduler.isPending)
    }

    func testScheduleThenFlushRunsOnce() async {
        let counter = Counter()
        let scheduler = AutosaveScheduler(interval: .seconds(100)) {
            counter.count += 1
        }
        scheduler.schedule()
        scheduler.schedule()
        scheduler.schedule()
        await scheduler.flush()
        XCTAssertEqual(counter.count, 1)
    }

    func testCancelPreventsSave() async {
        let counter = Counter()
        let scheduler = AutosaveScheduler(interval: .milliseconds(10)) {
            counter.count += 1
        }
        scheduler.schedule()
        scheduler.cancel()
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(counter.count, 0)
    }

    func testDebounceFiresOnceAfterQuiescence() async {
        let counter = Counter()
        let scheduler = AutosaveScheduler(interval: .milliseconds(30)) {
            counter.count += 1
        }
        // Rapid edits should coalesce into a single fire.
        scheduler.schedule()
        scheduler.schedule()
        scheduler.schedule()
        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(counter.count, 1)
        XCTAssertFalse(scheduler.isPending)
    }

    // MARK: - Dirty-guarded autosave

    func testAutosaveIfNeededSkipsCleanDocument() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LumenAutosave-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let url = root.appendingPathComponent("n.md")
        try "x".write(to: url, atomically: true, encoding: .utf8)
        let session = DocumentSession(files: FileService())
        try await session.open(url)

        let wroteWhenClean = try await session.autosaveIfNeeded()
        XCTAssertFalse(wroteWhenClean)

        session.text = "x changed"
        let wroteWhenDirty = try await session.autosaveIfNeeded()
        XCTAssertTrue(wroteWhenDirty)
        XCTAssertFalse(session.isDirty)
    }
}
