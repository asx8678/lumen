//
//  FileServiceEdgeCaseTests.swift
//  LumenCoreTests
//
//  P1.20 sweep — File IO edge cases beyond the happy-path FileServiceTests:
//  deep nesting, empty dirs, .lumen/.git exclusion, new-file write, write to a
//  missing parent, and uniquify chains for createNote/createFolder.
//

import Foundation
import XCTest

@testable import LumenCore

final class FileServiceEdgeCaseTests: XCTestCase {
    private var root: URL!
    private let files = FileService()

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LumenFSEdge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    private func mkdir(_ rel: String) throws {
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(rel), withIntermediateDirectories: true)
    }
    private func touch(_ rel: String, _ contents: String = "x") throws {
        try contents.write(
            to: root.appendingPathComponent(rel), atomically: true, encoding: .utf8)
    }

    // MARK: - enumerate

    func testEnumerateEmptyDirectory() async throws {
        let items = try await files.enumerate(root)
        XCTAssertTrue(items.isEmpty)
    }

    func testEnumerateDeepNestingPreservesTree() async throws {
        try mkdir("a/b/c")
        try touch("a/b/c/deep.md")
        try touch("a/top.md")

        let items = try await files.enumerate(root)
        // root has one folder "a"
        XCTAssertEqual(items.count, 1)
        let a = try XCTUnwrap(items.first { $0.name == "a" })
        XCTAssertTrue(a.isDirectory)
        // a contains top.md + folder b
        XCTAssertNotNil(a.children.first { $0.name == "top.md" && $0.kind == .markdown })
        let b = try XCTUnwrap(a.children.first { $0.name == "b" })
        let c = try XCTUnwrap(b.children.first { $0.name == "c" })
        XCTAssertNotNil(c.children.first { $0.name == "deep.md" })
    }

    func testEnumerateExcludesLumenAndGit() async throws {
        try mkdir(".lumen")
        try touch(".lumen/index.sqlite")
        try mkdir(".git")
        try touch(".git/HEAD")
        try touch(".hiddenfile.md")
        try touch("visible.md")

        let items = try await files.enumerate(root)
        XCTAssertEqual(items.map(\.name), ["visible.md"])
    }

    func testEnumerateMixedKinds() async throws {
        try touch("note.md")
        try touch("doc.markdown")
        try touch("image.png")
        let items = try await files.enumerate(root)
        let kinds = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.kind) })
        XCTAssertEqual(kinds["note.md"], .markdown)
        XCTAssertEqual(kinds["doc.markdown"], .markdown)
        XCTAssertEqual(kinds["image.png"], .other)
    }

    // MARK: - write

    func testWriteCreatesNewFile() async throws {
        let url = root.appendingPathComponent("fresh.md")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        try await files.write("hello", to: url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "hello")
    }

    func testWriteToMissingParentThrowsIOFailed() async throws {
        let url = root.appendingPathComponent("does/not/exist.md")
        do {
            try await files.write("x", to: url)
            XCTFail("expected ioFailed")
        } catch let error as FileServiceError {
            guard case .ioFailed = error else { return XCTFail("wrong error: \(error)") }
        }
    }

    // MARK: - uniquify chains

    func testCreateNoteUniquifyChain() async throws {
        let first = try await files.createNote(in: root)
        let second = try await files.createNote(in: root)
        let third = try await files.createNote(in: root)
        let names = [first, second, third].map(\.lastPathComponent)
        XCTAssertEqual(names, ["Untitled.md", "Untitled 1.md", "Untitled 2.md"])
    }

    func testCreateFolderUniquifyChain() async throws {
        let a = try await files.createFolder(in: root, named: "Notes")
        let b = try await files.createFolder(in: root, named: "Notes")
        XCTAssertEqual(a.lastPathComponent, "Notes")
        XCTAssertEqual(b.lastPathComponent, "Notes 1")
        XCTAssertTrue(FileManager.default.fileExists(atPath: b.path))
    }

    func testCreateNoteInMissingDirectoryThrows() async throws {
        let dir = root.appendingPathComponent("nope", isDirectory: true)
        do {
            _ = try await files.createNote(in: dir)
            XCTFail("expected ioFailed")
        } catch let error as FileServiceError {
            guard case .ioFailed = error else { return XCTFail("wrong error: \(error)") }
        }
    }

    // MARK: - rename

    func testRenameWhitespaceOnlyNameThrows() async throws {
        try touch("a.md")
        do {
            _ = try await files.rename(root.appendingPathComponent("a.md"), to: "   ")
            XCTFail("expected invalidName")
        } catch let error as FileServiceError {
            XCTAssertEqual(error, .invalidName)
        }
    }
}
