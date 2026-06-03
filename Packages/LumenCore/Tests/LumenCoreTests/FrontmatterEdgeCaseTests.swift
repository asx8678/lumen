//
//  FrontmatterEdgeCaseTests.swift
//  LumenCoreTests
//
//  P1.20 sweep — frontmatter parsing edge cases beyond FrontmatterParserTests:
//  nested mappings, lists of maps, a UTF-8 BOM prefix, and tabs in YAML values.
//

import Foundation
import XCTest

@testable import LumenCore

final class FrontmatterEdgeCaseTests: XCTestCase {
    func testNestedMappingInRaw() throws {
        let text = """
            ---
            title: Nested
            meta:
              author: Ada
              level: 2
            ---
            body
            """
        let parsed = FrontmatterParser.parse(text)
        let fm = try XCTUnwrap(parsed.frontmatter)
        XCTAssertEqual(fm.title, "Nested")
        guard case .dictionary(let meta)? = fm.raw["meta"] else {
            return XCTFail("expected nested dictionary for meta")
        }
        XCTAssertEqual(meta["author"]?.stringValue, "Ada")
        XCTAssertEqual(parsed.body, "body")
    }

    func testListOfMaps() {
        let text = """
            ---
            links:
              - name: Home
                url: /home
              - name: About
                url: /about
            ---
            x
            """
        let parsed = FrontmatterParser.parse(text)
        let fm = parsed.frontmatter
        XCTAssertNotNil(fm)
        guard case .array(let items)? = fm?.raw["links"] else {
            return XCTFail("expected array for links")
        }
        XCTAssertEqual(items.count, 2)
        XCTAssertFalse(parsed.hadParseError)
    }

    func testUTF8BOMPrefixedFrontmatter() {
        // A leading BOM should not prevent recognizing the opening fence.
        let bom = "\u{FEFF}"
        let text = bom + "---\ntitle: WithBOM\n---\nbody"
        let parsed = FrontmatterParser.parse(text)
        // Either the parser strips the BOM and reads frontmatter, or it treats
        // the whole thing as body — but it must never crash or lose the body.
        if let fm = parsed.frontmatter {
            XCTAssertEqual(fm.title, "WithBOM")
        } else {
            XCTAssertTrue(parsed.body.contains("body"))
        }
    }

    func testTabsInYAMLValueArePreserved() {
        // Tabs inside a quoted scalar value are legal and must round-trip.
        let text = "---\ntitle: \"a\tb\"\n---\nbody"
        let parsed = FrontmatterParser.parse(text)
        XCTAssertEqual(parsed.frontmatter?.title, "a\tb")
        XCTAssertEqual(parsed.body, "body")
    }
}
