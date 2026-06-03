//
//  main.swift
//  lumen-bench
//
//  Command-line entry point for Lumen performance benchmarks. P1.3 ships the
//  harness skeleton with ONE trivial smoke benchmark to prove it runs
//  end-to-end. Real benchmarks (e.g. large-vault launch/typing — P1.22) plug in
//  here later.
//

import Foundation
import LumenBenchmark

print("lumen-bench — Lumen performance harness (skeleton)")
print(String(repeating: "-", count: 52))

// Smoke benchmark 1: synthetic document generation.
let docResult = Benchmark.measure("generate 10k-line Markdown doc", iterations: 5) {
    _ = SyntheticData.markdownDocument(lineCount: 10_000)
}
print(docResult.summary)

// Smoke benchmark 2: synthetic vault generation + cleanup (filesystem touch).
let vaultResult = Benchmark.measure("generate + cleanup 50-file vault", iterations: 3) {
    if let vault = try? SyntheticData.makeVault(fileCount: 50) {
        vault.cleanup()
    }
}
print(vaultResult.summary)

print(String(repeating: "-", count: 52))
print("OK — harness ran \(docResult.iterations + vaultResult.iterations) measured iterations.")
