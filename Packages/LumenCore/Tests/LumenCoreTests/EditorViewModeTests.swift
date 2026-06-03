//
//  EditorViewModeTests.swift
//  LumenCoreTests
//
//  P2.2.1g: the per-tab three-way view mode (Source / Live Preview / Reading) —
//  toggle behavior, the DocumentSession transitions, back-compat decode of
//  legacy `edit`/`reading` snapshots, and the persistence round-trip.
//

import Foundation
import XCTest

@testable import LumenCore

final class EditorViewModeTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/Vault")

    // MARK: - Model helpers

    func testEditingModeToggleFlips() {
        XCTAssertEqual(EditorViewMode.source.toggledEditingMode, .livePreview)
        XCTAssertEqual(EditorViewMode.livePreview.toggledEditingMode, .source)
        // Reading falls back to source.
        XCTAssertEqual(EditorViewMode.reading.toggledEditingMode, .source)
    }

    func testIsEditing() {
        XCTAssertTrue(EditorViewMode.source.isEditing)
        XCTAssertTrue(EditorViewMode.livePreview.isEditing)
        XCTAssertFalse(EditorViewMode.reading.isEditing)
    }

    // MARK: - Back-compat decode

    func testLegacyEditRawValueDecodesToSource() {
        XCTAssertEqual(EditorViewMode(persistedRawValue: "edit"), .source)
        XCTAssertEqual(EditorViewMode(persistedRawValue: "source"), .source)
        XCTAssertEqual(EditorViewMode(persistedRawValue: "livePreview"), .livePreview)
        XCTAssertEqual(EditorViewMode(persistedRawValue: "reading"), .reading)
        XCTAssertEqual(EditorViewMode(persistedRawValue: "garbage"), .source)
    }

    func testLegacyModeArrayDecodes() throws {
        // A snapshot whose viewModes were persisted as the legacy "edit"/"reading".
        let json =
            #"{"relativePaths":["a.md","b.md"],"activeIndex":1,"viewModes":["edit","reading"]}"#
        let snapshot = try JSONDecoder().decode(TabsSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(snapshot.viewModes, [.source, .reading])
    }

    func testEncodesCurrentRawValues() throws {
        let data = try JSONEncoder().encode(EditorViewMode.livePreview)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "\"livePreview\"")
    }

    // MARK: - DocumentSession transitions

    @MainActor
    func testReadingToggleRoundTripsPreservingEditingMode() {
        let session = DocumentSession(files: FileService())
        XCTAssertEqual(session.viewMode, .source, "tabs default to source")

        // Source -> Reading -> back to Source.
        session.toggleReadingView()
        XCTAssertEqual(session.viewMode, .reading)
        session.toggleReadingView()
        XCTAssertEqual(session.viewMode, .source)

        // Live Preview is remembered across a reading round-trip.
        session.setViewMode(.livePreview)
        session.toggleReadingView()
        XCTAssertEqual(session.viewMode, .reading)
        session.toggleReadingView()
        XCTAssertEqual(session.viewMode, .livePreview)
    }

    @MainActor
    func testToggleEditingModeSwitchesSourceAndLivePreview() {
        let session = DocumentSession(files: FileService())
        session.toggleEditingMode()
        XCTAssertEqual(session.viewMode, .livePreview)
        session.toggleEditingMode()
        XCTAssertEqual(session.viewMode, .source)
    }

    @MainActor
    func testToggleEditingModeFromReadingLeavesReading() {
        let session = DocumentSession(files: FileService())
        session.setViewMode(.livePreview)
        session.setViewMode(.reading)
        // From reading, switching editing mode toggles the remembered mode.
        session.toggleEditingMode()
        XCTAssertEqual(session.viewMode, .source)
    }

    // MARK: - Persistence round-trip

    func testSnapshotPersistsViewModes() {
        let suite = "ViewModeTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = TabStore(defaults: defaults)
        let snapshot = TabsSnapshot(
            relativePaths: ["a.md", "b.md", "c.md"],
            activeIndex: 1,
            viewModes: [.source, .livePreview, .reading])
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
        XCTAssertEqual(snapshot.viewMode(at: 0), .source)
        XCTAssertEqual(snapshot.viewMode(at: 99), .source)
    }

    func testResolveCarriesModesAlignedToSurvivors() {
        // [a,b,c] modes [reading,livePreview,source]; b missing -> [a,c] [reading,source].
        let snapshot = TabsSnapshot(
            relativePaths: ["a.md", "b.md", "c.md"],
            activeIndex: 0,
            viewModes: [.reading, .livePreview, .source])
        let present: Set<String> = ["a.md", "c.md"]
        let result = TabStore.resolve(snapshot, vaultRoot: root) { url in
            present.contains(TabSupport.relativePath(of: url, root: root) ?? "")
        }
        XCTAssertEqual(result.modes, [.reading, .source])
        XCTAssertEqual(result.urls.count, 2)
    }
}
