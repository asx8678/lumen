//
//  VaultTests.swift
//  LumenCoreTests
//
//  P1.4: unit tests for the Vault model, recent-vaults policy, bookmark
//  round-trip, and VaultManager persistence/reopen behavior.
//

import Foundation
import XCTest

@testable import LumenCore

final class VaultTests: XCTestCase {
    // MARK: - Vault model

    func testVaultDefaultNameIsFolderName() {
        let vault = Vault(root: URL(fileURLWithPath: "/tmp/MyNotes"))
        XCTAssertEqual(vault.name, "MyNotes")
        XCTAssertEqual(vault.id, vault.root)
    }

    // MARK: - RecentVaultsPolicy

    private func recent(_ path: String) -> RecentVault {
        RecentVault(
            name: (path as NSString).lastPathComponent,
            path: path,
            bookmark: Data(path.utf8))
    }

    func testAddingPrependsAndDedupes() {
        var list: [RecentVault] = []
        list = RecentVaultsPolicy.updating(list, adding: recent("/a"))
        list = RecentVaultsPolicy.updating(list, adding: recent("/b"))
        list = RecentVaultsPolicy.updating(list, adding: recent("/a"))  // re-open /a
        XCTAssertEqual(list.map(\.path), ["/a", "/b"])
    }

    func testCapIsEnforced() {
        var list: [RecentVault] = []
        for i in 0..<15 {
            list = RecentVaultsPolicy.updating(list, adding: recent("/v\(i)"))
        }
        XCTAssertEqual(list.count, RecentVaultsPolicy.cap)
        XCTAssertEqual(list.first?.path, "/v14")  // most recent at front
        XCTAssertEqual(list.last?.path, "/v5")  // oldest retained
    }

    func testRemoving() {
        var list = [recent("/a"), recent("/b"), recent("/c")]
        list = RecentVaultsPolicy.removing(list, path: "/b")
        XCTAssertEqual(list.map(\.path), ["/a", "/c"])
    }

    func testRecentVaultCodableRoundTrip() throws {
        let original = recent("/tmp/Vault")
        let data = try JSONEncoder().encode([original])
        let decoded = try JSONDecoder().decode([RecentVault].self, from: data)
        XCTAssertEqual(decoded, [original])
    }

    // MARK: - Bookmark round-trip (non-scoped path)

    /// `.withSecurityScope` bookmarks generally cannot be resolved outside a
    /// sandboxed process, so this test exercises the plain (non-scoped) bookmark
    /// encode→resolve round-trip on a real temp directory to validate the
    /// mechanism. The scoped variant is exercised by the running sandboxed app.
    func testBookmarkRoundTripNonScoped() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LumenVaultTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let bookmark = try tmp.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil)
        var isStale = false
        let resolved = try URL(
            resolvingBookmarkData: bookmark,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale)
        XCTAssertEqual(resolved.standardizedFileURL.path, tmp.standardizedFileURL.path)
    }

    // MARK: - VaultManager persistence

    @MainActor
    func testManagerPersistsRecentsAcrossInstances() throws {
        let suiteName = "LumenVaultTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create test UserDefaults suite")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Seed a recents list directly via the persisted key shape.
        let seeded = [recent("/tmp/One"), recent("/tmp/Two")]
        let data = try JSONEncoder().encode(seeded)
        defaults.set(data, forKey: "LumenCore.recentVaults")

        // A fresh manager (no reopen) should load the persisted recents.
        let manager = VaultManager(defaults: defaults, reopenLast: false)
        XCTAssertEqual(manager.recents.map(\.path), ["/tmp/One", "/tmp/Two"])
        XCTAssertNil(manager.current)
    }

    @MainActor
    func testReopenLastDropsMissingFolderGracefully() {
        let suiteName = "LumenVaultTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create test UserDefaults suite")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Bookmark pointing at a path that does not exist → reopen must not crash.
        let bogus = RecentVault(
            name: "Gone", path: "/nonexistent/Gone",
            bookmark: Data("bogus".utf8))
        if let data = try? JSONEncoder().encode([bogus]) {
            defaults.set(data, forKey: "LumenCore.recentVaults")
        }
        let manager = VaultManager(defaults: defaults, reopenLast: true)
        XCTAssertNil(manager.current, "Missing vault must not become current")
    }
}
