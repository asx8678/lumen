//
//  WikilinkResolverTests.swift
//  LumenCoreTests
//
//  lumen-gia: pure wikilink target → note path resolution (name match, alias,
//  heading/block stripping, path match, ambiguity tie-break, missing target).
//

import XCTest

@testable import LumenCore

final class WikilinkResolverTests: XCTestCase {
    private let vault = [
        "Daily/2026-06-03.md",
        "notes/Project Ideas.md",
        "notes/archive/Project Ideas.md",
        "Reference/Swift.md",
        "Reference/sub/Swift.md",
        "index.md",
    ]

    func testResolvesByBasename() {
        XCTAssertEqual(
            WikilinkResolver.resolve(target: "Swift", among: vault),
            "Reference/Swift.md")
    }

    func testResolvesIsCaseInsensitive() {
        XCTAssertEqual(
            WikilinkResolver.resolve(target: "swift", among: vault),
            "Reference/Swift.md")
    }

    func testStripsAlias() {
        XCTAssertEqual(
            WikilinkResolver.resolve(target: "Swift|the language", among: vault),
            "Reference/Swift.md")
    }

    func testStripsHeadingAndBlockReferences() {
        XCTAssertEqual(
            WikilinkResolver.resolve(target: "Swift#Concurrency", among: vault),
            "Reference/Swift.md")
        XCTAssertEqual(
            WikilinkResolver.resolve(target: "Swift#^abc123", among: vault),
            "Reference/Swift.md")
    }

    func testExactPathMatchPreferredOverBasename() {
        XCTAssertEqual(
            WikilinkResolver.resolve(target: "notes/archive/Project Ideas", among: vault),
            "notes/archive/Project Ideas.md")
    }

    func testAmbiguousBasenamePicksShortestPathDeterministically() {
        // Two "Project Ideas.md" — the shallower path wins deterministically.
        XCTAssertEqual(
            WikilinkResolver.resolve(target: "Project Ideas", among: vault),
            "notes/Project Ideas.md")
    }

    func testMissingTargetReturnsNil() {
        XCTAssertNil(WikilinkResolver.resolve(target: "Nonexistent", among: vault))
    }

    func testEmptyTargetReturnsNil() {
        XCTAssertNil(WikilinkResolver.resolve(target: "", among: vault))
        XCTAssertNil(WikilinkResolver.resolve(target: "#heading-only", among: vault))
    }

    func testNoteNameStripsExtensionAliasAndHeading() {
        XCTAssertEqual(WikilinkResolver.noteName(from: "Swift.md"), "Swift")
        XCTAssertEqual(WikilinkResolver.noteName(from: "Folder/Note#H|alias"), "Folder/Note")
    }
}
