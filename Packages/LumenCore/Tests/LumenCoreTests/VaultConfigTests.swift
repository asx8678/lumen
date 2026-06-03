//
//  VaultConfigTests.swift
//  LumenCoreTests
//
//  P1.19: per-vault config Codable round-trip, defaults, missing-file load,
//  save/load through `.lumen/`, and new-note-location resolution + layering.
//

import Foundation
import XCTest

@testable import LumenCore

final class VaultConfigTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LumenVaultConfig-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    func testDefaults() {
        XCTAssertNil(VaultConfig.default.defaultNoteLocation)
        XCTAssertEqual(VaultConfig.default.defaultNoteDirectory(vaultRoot: root), root)
    }

    func testCodableRoundTrip() throws {
        let original = VaultConfig(defaultNoteLocation: "Inbox/Daily")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VaultConfig.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func testLoadMissingFileReturnsDefault() {
        // No config written yet.
        XCTAssertEqual(VaultConfigStore.load(vaultRoot: root), .default)
    }

    func testSaveThenLoadRoundTrip() throws {
        var config = VaultConfig()
        config.defaultNoteLocation = "Notes"
        try VaultConfigStore.save(config, vaultRoot: root)

        // It lives under .lumen/ and is human-readable JSON.
        let url = VaultConfigStore.configURL(forVaultRoot: root)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, ".lumen")
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("defaultNoteLocation"))
        XCTAssertTrue(text.contains("Notes"))

        XCTAssertEqual(VaultConfigStore.load(vaultRoot: root), config)
    }

    func testNoteDirectoryResolution() {
        let configured = VaultConfig(defaultNoteLocation: "Inbox")
        XCTAssertEqual(
            configured.defaultNoteDirectory(vaultRoot: root),
            root.appendingPathComponent("Inbox", isDirectory: true))

        // Empty/whitespace falls back to the root.
        XCTAssertEqual(
            VaultConfig(defaultNoteLocation: "  ").defaultNoteDirectory(vaultRoot: root), root)
    }

    func testCorruptFileLoadsDefault() throws {
        let dir = root.appendingPathComponent(".lumen", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "not json".write(
            to: dir.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
        XCTAssertEqual(VaultConfigStore.load(vaultRoot: root), .default)
    }
}
