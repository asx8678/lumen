//
//  TabSupportTests.swift
//  LumenCoreTests
//
//  P1.16: active-tab reselection, relative-path mapping, and the
//  persist→restore round-trip (including skipping a missing file).
//

import Foundation
import XCTest

@testable import LumenCore

final class TabSupportTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/Vault")

    // MARK: - Active reselection

    func testActiveIndexAfterRemovingMiddle() {
        // [0,1,2] remove index 1 -> remaining 2, active = min(1,1) = 1
        XCTAssertEqual(TabSupport.activeIndexAfterRemoving(1, count: 3), 1)
    }

    func testActiveIndexAfterRemovingLast() {
        // [0,1,2] remove index 2 -> remaining 2, active = min(2,1) = 1
        XCTAssertEqual(TabSupport.activeIndexAfterRemoving(2, count: 3), 1)
    }

    func testActiveIndexAfterRemovingFirst() {
        XCTAssertEqual(TabSupport.activeIndexAfterRemoving(0, count: 3), 0)
    }

    func testActiveIndexAfterRemovingOnlyTab() {
        XCTAssertNil(TabSupport.activeIndexAfterRemoving(0, count: 1))
    }

    // MARK: - Relative paths

    func testRelativePathUnderRoot() {
        let url = root.appendingPathComponent("notes/a.md")
        XCTAssertEqual(TabSupport.relativePath(of: url, root: root), "notes/a.md")
    }

    func testRelativePathOutsideRootIsNil() {
        XCTAssertNil(TabSupport.relativePath(of: URL(fileURLWithPath: "/Other/a.md"), root: root))
    }

    func testResolveRoundTrip() {
        let url = root.appendingPathComponent("sub/deep/b.md")
        let rel = TabSupport.relativePath(of: url, root: root)
        let back = TabSupport.resolve(relativePath: rel ?? "", root: root)
        XCTAssertEqual(back.standardizedFileURL.path, url.standardizedFileURL.path)
    }

    // MARK: - Persist / restore round-trip

    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "TabStoreTests-\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    func testSaveLoadRoundTrip() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = TabStore(defaults: defaults)
        let snapshot = TabsSnapshot(relativePaths: ["a.md", "b.md"], activeIndex: 1)
        store.save(snapshot, vaultRoot: root)
        XCTAssertEqual(store.load(vaultRoot: root), snapshot)
    }

    func testLoadMissingReturnsEmpty() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(TabStore(defaults: defaults).load(vaultRoot: root), .empty)
    }

    func testResolveSkipsMissingAndRemapsActive() {
        // Persisted [a,b,c] active=2 (c). b is missing -> survivors [a,c], active=c -> index 1.
        let snapshot = TabsSnapshot(relativePaths: ["a.md", "b.md", "c.md"], activeIndex: 2)
        let present: Set<String> = ["a.md", "c.md"]
        let result = TabStore.resolve(snapshot, vaultRoot: root) { url in
            present.contains(TabSupport.relativePath(of: url, root: root) ?? "")
        }
        XCTAssertEqual(
            result.urls.map { TabSupport.relativePath(of: $0, root: root) }, ["a.md", "c.md"])
        XCTAssertEqual(result.activeIndex, 1)
    }

    func testResolveAllMissingYieldsNilActive() {
        let snapshot = TabsSnapshot(relativePaths: ["x.md"], activeIndex: 0)
        let result = TabStore.resolve(snapshot, vaultRoot: root) { _ in false }
        XCTAssertTrue(result.urls.isEmpty)
        XCTAssertNil(result.activeIndex)
    }

    func testResolveActiveWasRemovedFallsBack() {
        // active=1 (b) removed -> survivors [a,c]; active should fall to a (index 0).
        let snapshot = TabsSnapshot(relativePaths: ["a.md", "b.md", "c.md"], activeIndex: 1)
        let present: Set<String> = ["a.md", "c.md"]
        let result = TabStore.resolve(snapshot, vaultRoot: root) { url in
            present.contains(TabSupport.relativePath(of: url, root: root) ?? "")
        }
        XCTAssertEqual(result.activeIndex, 0)
    }
}
