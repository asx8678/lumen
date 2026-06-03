//
//  LivePreviewImageResolverTests.swift
//  LumenEditorTests
//
//  lumen-gia: pure inline-image source → loadable URL resolution (remote vs
//  vault-relative vs missing), mirroring the reading view's rule.
//

import XCTest

@testable import LumenEditor

final class LivePreviewImageResolverTests: XCTestCase {
    private let base = URL(fileURLWithPath: "/Vault/Notes/", isDirectory: true)

    func testRemoteURLPassesThrough() {
        let url = LivePreviewImageResolver.resolvedURL(
            source: "https://example.com/cat.png", baseURL: base)
        XCTAssertEqual(url?.absoluteString, "https://example.com/cat.png")
        XCTAssertEqual(LivePreviewImageResolver.isLocalFile(url ?? base), false)
    }

    func testVaultRelativePathResolvesAgainstBase() {
        let url = LivePreviewImageResolver.resolvedURL(
            source: "images/tabby.png", baseURL: base)
        XCTAssertEqual(url?.path, "/Vault/Notes/images/tabby.png")
        XCTAssertTrue(LivePreviewImageResolver.isLocalFile(url ?? base))
    }

    func testParentRelativePathResolves() {
        let url = LivePreviewImageResolver.resolvedURL(
            source: "../assets/pic.png", baseURL: base)
        XCTAssertEqual(url?.standardizedFileURL.path, "/Vault/assets/pic.png")
    }

    func testEmptySourceReturnsNil() {
        XCTAssertNil(LivePreviewImageResolver.resolvedURL(source: "", baseURL: base))
        XCTAssertNil(LivePreviewImageResolver.resolvedURL(source: "   ", baseURL: base))
    }

    func testNoBaseURLFallsBackToBareURL() {
        let url = LivePreviewImageResolver.resolvedURL(source: "pic.png", baseURL: nil)
        XCTAssertEqual(url?.absoluteString, "pic.png")
    }
}
