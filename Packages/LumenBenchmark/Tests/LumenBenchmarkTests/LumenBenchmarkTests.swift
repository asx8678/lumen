//
//  LumenBenchmarkTests.swift
//  LumenBenchmarkTests
//
//  P1.3: smoke tests proving the harness (generators + measurement) works
//  end-to-end. Real perf assertions live with their features (P1.22).
//

import Foundation
import XCTest

@testable import LumenBenchmark

final class LumenBenchmarkTests: XCTestCase {
    func testMarkdownDocumentHasApproxLineCount() {
        let doc = SyntheticData.markdownDocument(lineCount: 1_000)
        let lines = doc.split(separator: "\n", omittingEmptySubsequences: false).count
        XCTAssertEqual(lines, 1_000)
    }

    func testMakeVaultCreatesFiles() throws {
        let vault = try SyntheticData.makeVault(fileCount: 12, subfolders: 3)
        defer { vault.cleanup() }
        XCTAssertEqual(vault.files.count, 12)
        for file in vault.files {
            XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        }
        // Cleanup actually removes the tree.
        vault.cleanup()
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.root.path))
    }

    func testBenchmarkMeasureProducesSamples() {
        let result = Benchmark.measure("noop", iterations: 4, warmup: 1) {
            _ = (0..<100).reduce(0, +)
        }
        XCTAssertEqual(result.iterations, 4)
        XCTAssertEqual(result.samples.count, 4)
        XCTAssertGreaterThanOrEqual(result.mean, 0)
        XCTAssertFalse(result.summary.isEmpty)
    }
}
