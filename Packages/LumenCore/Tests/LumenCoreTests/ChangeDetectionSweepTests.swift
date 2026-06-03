//
//  ChangeDetectionSweepTests.swift
//  LumenCoreTests
//
//  P1.20 sweep — change detection (NoteIndexing): hash authority over the size
//  shortcut, unicode-content stability/sensitivity, and large-content hashing.
//

import Foundation
import XCTest

@testable import LumenCore

final class ChangeDetectionSweepTests: XCTestCase {
    func testHashIsAuthoritativeWhenSizeUnchanged() {
        // Two same-length strings with different content must hash differently,
        // so needsReindex triggers even though the size shortcut would match.
        let a = "abcd"
        let b = "abce"
        XCTAssertEqual(a.utf8.count, b.utf8.count)
        let hashA = NoteIndexing.contentHash(of: a)
        let hashB = NoteIndexing.contentHash(of: b)
        XCTAssertNotEqual(hashA, hashB)

        // Stored record has size 4 + hashA; a same-size edit (hashB) reindexes.
        let existing = NoteRecord(
            path: "n.md", title: nil, mtime: 100, size: 4, frontmatter: nil, contentHash: hashA)
        let needs = NoteIndexing.needsReindex(
            existing: existing, mtime: 100, size: 4, hash: hashB)
        XCTAssertTrue(needs)
    }

    func testNoReindexWhenHashMatchesEvenIfMtimeMoved() {
        let hash = NoteIndexing.contentHash(of: "stable")
        let existing = NoteRecord(
            path: "n.md", title: nil, mtime: 100, size: 6, frontmatter: nil, contentHash: hash)
        let needs = NoteIndexing.needsReindex(
            existing: existing, mtime: 999, size: 6, hash: hash)
        XCTAssertFalse(needs)
    }

    func testUnicodeContentHashStableAndSensitive() {
        let text = "cafe\u{0301} \u{65e5}\u{672c}\u{8a9e} note"
        XCTAssertEqual(
            NoteIndexing.contentHash(of: text), NoteIndexing.contentHash(of: text))
        XCTAssertNotEqual(
            NoteIndexing.contentHash(of: text),
            NoteIndexing.contentHash(of: text + " "))
    }

    func testLargeContentHashes() {
        let big = String(repeating: "lorem ipsum dolor sit amet\n", count: 50_000)
        let hash = NoteIndexing.contentHash(of: big)
        XCTAssertFalse(hash.isEmpty)
        // Changing a single character deep in the document changes the hash.
        var mutated = big
        mutated.replaceSubrange(
            mutated.startIndex...mutated.startIndex, with: "L")
        XCTAssertNotEqual(hash, NoteIndexing.contentHash(of: mutated))
    }
}
