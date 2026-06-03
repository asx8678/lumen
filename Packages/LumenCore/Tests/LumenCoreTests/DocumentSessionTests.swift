//
//  DocumentSessionTests.swift
//  LumenCoreTests
//
//  P1.15: open-document model load/save/dirty transitions + target-folder
//  resolution.
//

import Foundation
import XCTest

@testable import LumenCore

final class DocumentSessionTests: XCTestCase {
    private var root: URL!
    private let files = FileService()

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LumenDocSessionTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root, FileManager.default.fileExists(atPath: root.path) {
            try? FileManager.default.removeItem(at: root)
        }
    }

    @MainActor
    func testOpenLoadsContentNotDirty() async throws {
        let url = root.appendingPathComponent("note.md")
        try "hello".write(to: url, atomically: true, encoding: .utf8)

        let session = DocumentSession(files: files)
        try await session.open(url)
        XCTAssertEqual(session.text, "hello")
        XCTAssertEqual(session.url, url)
        XCTAssertFalse(session.isDirty)
    }

    @MainActor
    func testEditingMarksDirtyAndSaveClears() async throws {
        let url = root.appendingPathComponent("note.md")
        try "hello".write(to: url, atomically: true, encoding: .utf8)

        let session = DocumentSession(files: files)
        try await session.open(url)

        session.text = "hello world"
        XCTAssertTrue(session.isDirty)

        try await session.save()
        XCTAssertFalse(session.isDirty)

        // Persisted to disk.
        let onDisk = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(onDisk, "hello world")
    }

    @MainActor
    func testRevertingTextClearsDirty() async throws {
        let url = root.appendingPathComponent("note.md")
        try "abc".write(to: url, atomically: true, encoding: .utf8)
        let session = DocumentSession(files: files)
        try await session.open(url)

        session.text = "changed"
        XCTAssertTrue(session.isDirty)
        session.text = "abc"  // back to saved baseline
        XCTAssertFalse(session.isDirty)
    }

    @MainActor
    func testSaveWithNothingOpenIsNoOp() async throws {
        let session = DocumentSession(files: files)
        try await session.save()  // must not throw
        XCTAssertNil(session.url)
    }

    @MainActor
    func testCloseResets() async throws {
        let url = root.appendingPathComponent("note.md")
        try "x".write(to: url, atomically: true, encoding: .utf8)
        let session = DocumentSession(files: files)
        try await session.open(url)
        session.close()
        XCTAssertNil(session.url)
        XCTAssertEqual(session.text, "")
        XCTAssertFalse(session.isDirty)
    }

    // MARK: - Target-folder resolution

    func testTargetFolderForFolderSelection() {
        let folder = VaultItem(url: root.appendingPathComponent("Sub"), kind: .folder)
        XCTAssertEqual(FileTreeSupport.targetFolder(for: folder, vaultRoot: root), folder.url)
    }

    func testTargetFolderForFileSelectionUsesParent() {
        let file = VaultItem(url: root.appendingPathComponent("Sub/a.md"), kind: .markdown)
        XCTAssertEqual(
            FileTreeSupport.targetFolder(for: file, vaultRoot: root).standardizedFileURL.path,
            root.appendingPathComponent("Sub").standardizedFileURL.path)
    }

    func testTargetFolderForNoSelectionUsesRoot() {
        XCTAssertEqual(FileTreeSupport.targetFolder(for: nil, vaultRoot: root), root)
    }
}
