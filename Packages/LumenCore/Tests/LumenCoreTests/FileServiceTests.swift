//
//  FileServiceTests.swift
//  LumenCoreTests
//
//  P1.5: unit tests for the file IO layer against temp directories
//  (FileManager works headlessly without sandbox).
//

import Foundation
import XCTest

@testable import LumenCore

final class FileServiceTests: XCTestCase {
    private var root: URL!
    private let service = FileService()

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LumenFileServiceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root, FileManager.default.fileExists(atPath: root.path) {
            try? FileManager.default.removeItem(at: root)
        }
    }

    private func write(_ text: String, _ relativePath: String) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Enumerate

    func testEnumerateDistinguishesKindsAndExcludesHidden() async throws {
        try write("# A", "note.md")
        try write("plain", "readme.markdown")
        try write("img-bytes", "image.png")
        try write("nested", "Folder/child.md")
        try write("secret", ".hidden.md")
        try write("cfg", ".lumen/config.json")
        try write("obj", ".git/HEAD")

        let items = try await service.enumerate(root)
        let topNames = Set(items.map(\.name))
        XCTAssertTrue(topNames.contains("note.md"))
        XCTAssertTrue(topNames.contains("readme.markdown"))
        XCTAssertTrue(topNames.contains("image.png"))
        XCTAssertTrue(topNames.contains("Folder"))
        XCTAssertFalse(topNames.contains(".hidden.md"), "hidden dotfiles must be skipped")
        XCTAssertFalse(topNames.contains(".lumen"), ".lumen must be skipped")
        XCTAssertFalse(topNames.contains(".git"), ".git must be skipped")

        let kindByName = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.kind) })
        XCTAssertEqual(kindByName["note.md"], .markdown)
        XCTAssertEqual(kindByName["readme.markdown"], .markdown)
        XCTAssertEqual(kindByName["image.png"], .other)
        XCTAssertEqual(kindByName["Folder"], .folder)

        let folder = try XCTUnwrap(items.first { $0.name == "Folder" })
        XCTAssertEqual(folder.children.map(\.name), ["child.md"])
        XCTAssertEqual(folder.children.first?.kind, .markdown)
    }

    // MARK: - Read / Write

    func testWriteThenReadRoundTrip() async throws {
        let url = root.appendingPathComponent("rt.md")
        let body = "# Title\n\nBody with unicode: café \n"
        try await service.write(body, to: url)
        let read = try await service.read(url)
        XCTAssertEqual(read, body)
    }

    func testAtomicWriteReplacesContentIntegrity() async throws {
        let url = root.appendingPathComponent("atomic.md")
        try await service.write(String(repeating: "old\n", count: 1000), to: url)
        let new = String(repeating: "new content line\n", count: 5000)
        try await service.write(new, to: url)
        let read = try await service.read(url)
        XCTAssertEqual(read, new)
        // File still exists and is exactly the new content (no truncation).
        XCTAssertEqual(read.count, new.count)
    }

    func testReadNonUTF8Throws() async throws {
        let url = root.appendingPathComponent("binary.dat")
        try Data([0xFF, 0xFE, 0xFD, 0xFC]).write(to: url)
        do {
            _ = try await service.read(url)
            XCTFail("Expected notUTF8")
        } catch let error as FileServiceError {
            XCTAssertEqual(error, .notUTF8)
        }
    }

    // MARK: - Trash

    func testMoveToTrashRemovesFromLocation() async throws {
        let url = root.appendingPathComponent("trash-me.md")
        try await service.write("bye", to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let resulting = try await service.moveToTrash(url)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: url.path),
            "item must be gone from its original location")
        // Clean up the trashed copy so we don't pollute the real Trash.
        if let resulting { try? FileManager.default.removeItem(at: resulting) }
    }

    // MARK: - Rename

    func testRenameMovesFile() async throws {
        let url = root.appendingPathComponent("before.md")
        try await service.write("x", to: url)
        let renamed = try await service.rename(url, to: "after.md")
        XCTAssertEqual(renamed.lastPathComponent, "after.md")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamed.path))
    }

    func testRenameCollisionUniquifies() async throws {
        let a = root.appendingPathComponent("a.md")
        let taken = root.appendingPathComponent("taken.md")
        try await service.write("a", to: a)
        try await service.write("taken", to: taken)
        let renamed = try await service.rename(a, to: "taken.md")
        XCTAssertEqual(renamed.lastPathComponent, "taken 1.md")
    }

    func testRenameEmptyNameThrows() async throws {
        let url = root.appendingPathComponent("x.md")
        try await service.write("x", to: url)
        do {
            _ = try await service.rename(url, to: "   ")
            XCTFail("Expected invalidName")
        } catch let error as FileServiceError {
            XCTAssertEqual(error, .invalidName)
        }
    }

    // MARK: - Create

    func testCreateNoteDefaultsAndUniquifies() async throws {
        let first = try await service.createNote(in: root)
        XCTAssertEqual(first.lastPathComponent, "Untitled.md")
        let second = try await service.createNote(in: root)
        XCTAssertEqual(second.lastPathComponent, "Untitled 1.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
    }

    func testCreateNoteAddsExtension() async throws {
        let url = try await service.createNote(in: root, named: "Meeting Notes")
        XCTAssertEqual(url.lastPathComponent, "Meeting Notes.md")
    }

    func testCreateFolderDefaultsAndUniquifies() async throws {
        let first = try await service.createFolder(in: root)
        XCTAssertEqual(first.lastPathComponent, "New Folder")
        let second = try await service.createFolder(in: root)
        XCTAssertEqual(second.lastPathComponent, "New Folder 1")
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
    }

    // MARK: - Sort helper

    func testSortByNameFoldersFirst() {
        let items = [
            VaultItem(url: URL(fileURLWithPath: "/z.md"), kind: .markdown),
            VaultItem(url: URL(fileURLWithPath: "/A"), kind: .folder),
            VaultItem(url: URL(fileURLWithPath: "/a.md"), kind: .markdown),
        ]
        let sorted = VaultItem.sorted(items, by: .name)
        XCTAssertEqual(sorted.map(\.name), ["A", "a.md", "z.md"])
    }
}
