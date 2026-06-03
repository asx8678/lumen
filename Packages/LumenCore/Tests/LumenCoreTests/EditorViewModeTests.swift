//
//  EditorViewModeTests.swift
//  LumenCoreTests
//
//  P2.1.1: the per-tab reading/edit mode — toggle behavior, the DocumentSession
//  flip, and persistence round-trip (including legacy snapshots without modes).
//

import Foundation
import XCTest

@testable import LumenCore

final class EditorViewModeTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/Vault")

    func testToggledFlips() {
        XCTAssertEqual(EditorViewMode.edit.toggled, .reading)
        XCTAssertEqual(EditorViewMode.reading.toggled, .edit)
    }

    @MainActor
    func testDocumentSessionTogglesMode() {
        let session = DocumentSession(files: FileService())
        XCTAssertEqual(session.viewMode, .edit, "tabs default to edit")
        session.toggleViewMode()
        XCTAssertEqual(session.viewMode, .reading)
        session.toggleViewMode()
        XCTAssertEqual(session.viewMode, .edit)
    }

    func testSnapshotPersistsViewModes() {
        let suite = "ViewModeTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = TabStore(defaults: defaults)
        let snapshot = TabsSnapshot(
            relativePaths: ["a.md", "b.md"],
            activeIndex: 1,
            viewModes: [.edit, .reading])
        store.save(snapshot, vaultRoot: root)
        XCTAssertEqual(store.load(vaultRoot: root), snapshot)
    }

    func testLegacySnapshotDecodesWithDefaultModes() throws {
        // A snapshot encoded before viewModes existed must still decode.
        let legacyJSON = #"{"relativePaths":["a.md","b.md"],"activeIndex":0}"#
        let data = Data(legacyJSON.utf8)
        let snapshot = try JSONDecoder().decode(TabsSnapshot.self, from: data)
        XCTAssertEqual(snapshot.relativePaths, ["a.md", "b.md"])
        XCTAssertTrue(snapshot.viewModes.isEmpty)
        XCTAssertEqual(snapshot.viewMode(at: 0), .edit)
        XCTAssertEqual(snapshot.viewMode(at: 99), .edit)
    }

    func testResolveCarriesModesAlignedToSurvivors() {
        // [a,b,c] with modes [reading,edit,reading]; b missing -> [a,c] modes [reading,reading].
        let snapshot = TabsSnapshot(
            relativePaths: ["a.md", "b.md", "c.md"],
            activeIndex: 0,
            viewModes: [.reading, .edit, .reading])
        let present: Set<String> = ["a.md", "c.md"]
        let result = TabStore.resolve(snapshot, vaultRoot: root) { url in
            present.contains(TabSupport.relativePath(of: url, root: root) ?? "")
        }
        XCTAssertEqual(result.modes, [.reading, .reading])
        XCTAssertEqual(result.urls.count, 2)
    }
}
