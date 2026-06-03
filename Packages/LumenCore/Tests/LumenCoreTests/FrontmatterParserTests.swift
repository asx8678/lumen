//
//  FrontmatterParserTests.swift
//  LumenCoreTests
//
//  P1.7: YAML frontmatter detection + parsing into a metadata snapshot.
//

import Foundation
import XCTest

@testable import LumenCore

final class FrontmatterParserTests: XCTestCase {
    // MARK: - Present

    func testTypedFieldsAndArbitraryKeys() {
        let text = """
            ---
            title: My Note
            tags: [swift, macos]
            aliases:
              - alt one
              - alt two
            custom: hello
            count: 42
            published: true
            ---
            # Body

            Content here.
            """
        let parsed = FrontmatterParser.parse(text)
        let fm = parsed.frontmatter
        XCTAssertNotNil(fm)
        XCTAssertEqual(fm?.title, "My Note")
        XCTAssertEqual(fm?.tags, ["swift", "macos"])
        XCTAssertEqual(fm?.aliases, ["alt one", "alt two"])
        XCTAssertEqual(fm?.raw["custom"], .string("hello"))
        XCTAssertEqual(fm?.raw["count"], .int(42))
        XCTAssertEqual(fm?.raw["published"], .bool(true))
        XCTAssertEqual(parsed.body, "# Body\n\nContent here.")
        XCTAssertEqual(parsed.frontmatterLineRange, 1...10)
        XCTAssertFalse(parsed.hadParseError)
    }

    func testTagsAsScalarNormalizeToArray() {
        let parsed = FrontmatterParser.parse("---\ntags: solo\n---\nbody")
        XCTAssertEqual(parsed.frontmatter?.tags, ["solo"])
    }

    func testBodyRangeReconstructsOriginal() {
        let text = "---\ntitle: X\n---\nhello world"
        let parsed = FrontmatterParser.parse(text)
        let range = try? XCTUnwrap(parsed.frontmatterRange)
        if let range {
            XCTAssertEqual(String(text[range]), "---\ntitle: X\n---\n")
            XCTAssertEqual(String(text[range.upperBound...]), "hello world")
        }
    }

    // MARK: - Absent

    func testNoFrontmatterReturnsFullBody() {
        let text = "# Just a heading\n\nNo frontmatter here."
        let parsed = FrontmatterParser.parse(text)
        XCTAssertNil(parsed.frontmatter)
        XCTAssertEqual(parsed.body, text)
        XCTAssertNil(parsed.frontmatterRange)
        XCTAssertFalse(parsed.hadParseError)
    }

    func testMidDocumentRuleIsNotFrontmatter() {
        let text = "Some intro text.\n\n---\n\nA horizontal rule above."
        let parsed = FrontmatterParser.parse(text)
        XCTAssertNil(parsed.frontmatter)
        XCTAssertEqual(parsed.body, text)
    }

    func testUnterminatedFenceIsNotFrontmatter() {
        let text = "---\ntitle: X\nbody with no closing fence"
        let parsed = FrontmatterParser.parse(text)
        XCTAssertNil(parsed.frontmatter)
        XCTAssertEqual(parsed.body, text)
    }

    // MARK: - Empty

    func testEmptyFrontmatter() {
        let text = "---\n---\nthe body"
        let parsed = FrontmatterParser.parse(text)
        XCTAssertNotNil(parsed.frontmatter)
        XCTAssertEqual(parsed.frontmatter?.raw, [:])
        XCTAssertEqual(parsed.frontmatter?.tags, [])
        XCTAssertEqual(parsed.body, "the body")
        XCTAssertFalse(parsed.hadParseError)
    }

    func testClosingWithEllipsis() {
        let parsed = FrontmatterParser.parse("---\ntitle: X\n...\nbody")
        XCTAssertEqual(parsed.frontmatter?.title, "X")
        XCTAssertEqual(parsed.body, "body")
    }

    // MARK: - Malformed

    func testMalformedYAMLPreservesBody() {
        let text = "---\ntitle: : : bad\n  - nope\n---\nimportant content"
        let parsed = FrontmatterParser.parse(text)
        // Body must never be lost; degrade to no-frontmatter + parse error flag.
        XCTAssertNil(parsed.frontmatter)
        XCTAssertTrue(parsed.hadParseError)
        XCTAssertEqual(parsed.body, text)
    }

    func testNonMappingRootIsParseError() {
        let text = "---\n- just\n- a\n- list\n---\nbody"
        let parsed = FrontmatterParser.parse(text)
        XCTAssertNil(parsed.frontmatter)
        XCTAssertTrue(parsed.hadParseError)
        XCTAssertEqual(parsed.body, text)
    }

    // MARK: - CRLF / whitespace

    func testCRLFLineEndings() {
        let text = "---\r\ntitle: Win\r\ntags: [a, b]\r\n---\r\nbody line"
        let parsed = FrontmatterParser.parse(text)
        XCTAssertEqual(parsed.frontmatter?.title, "Win")
        XCTAssertEqual(parsed.frontmatter?.tags, ["a", "b"])
        XCTAssertEqual(parsed.body, "body line")
    }

    func testTrailingWhitespaceOnFence() {
        let parsed = FrontmatterParser.parse("---   \ntitle: X\n---  \nbody")
        XCTAssertEqual(parsed.frontmatter?.title, "X")
        XCTAssertEqual(parsed.body, "body")
    }

    // MARK: - Dates

    func testDateParsing() {
        let parsed = FrontmatterParser.parse("---\ncreated: 2024-03-15\n---\nbody")
        XCTAssertNotNil(parsed.frontmatter?.created)
    }

    // MARK: - YAMLValue helpers

    func testYAMLValueNormalization() {
        XCTAssertEqual(YAMLValue.int(7).stringValue, "7")
        XCTAssertEqual(YAMLValue.string("hi").stringArray, ["hi"])
        XCTAssertEqual(
            YAMLValue.array([.string("a"), .int(2)]).stringArray, ["a", "2"])
    }
}
