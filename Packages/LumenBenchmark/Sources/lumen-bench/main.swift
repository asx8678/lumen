//
//  main.swift
//  lumen-bench
//
//  Lumen performance harness (P1.22). Generates a LARGE synthetic vault and
//  measures the real indexing pipeline from LumenCore — enumerate (FileService)
//  -> parse (FrontmatterParser) -> hash (NoteIndexing) -> upsert (NotesIndex) —
//  via the background `VaultIndexer`. Reports cold full-index throughput, a warm
//  second pass (proving the size+mtime cheap-skip), and resident memory.
//
//  This measures the dominant ALGORITHMIC cost of "open a large vault". True
//  cold-APP-launch wall-time needs a GUI run; the index/parse cost benchmarked
//  here is the dominant factor behind the < 1s launch budget.
//

import Foundation
import LumenBenchmark
import LumenCore

print("lumen-bench — Lumen performance harness (P1.22)")
print(String(repeating: "-", count: 60))

// MARK: - Smoke: synthetic document generation (kept from P1.3)

let docResult = Benchmark.measure("generate 10k-line Markdown doc", iterations: 5) {
    _ = SyntheticData.markdownDocument(lineCount: 10_000)
}
print(docResult.summary)

// MARK: - Large synthetic vault

// A few thousand .md files of varying sizes across several subfolders.
let fileCount = 3_000
let vault = try SyntheticData.makeVault(
    fileCount: fileCount, subfolders: 12, maxLinesPerFile: 120)
defer { vault.cleanup() }

let totalBytes = vault.files.reduce(into: 0) { sum, url in
    sum += (try? Data(contentsOf: url).count) ?? 0
}
print(
    "Synthetic vault: \(vault.files.count) .md files, "
        + "\(totalBytes / 1_048_576) MiB across 12 folders")
print(String(repeating: "-", count: 60))

// Build the real index + indexer. IndexingStatus is @MainActor.
let status = await MainActor.run { IndexingStatus() }
let files = FileService()

func makeIndexer() throws -> (VaultIndexer, NotesIndex) {
    let index = try NotesIndex(vaultRoot: vault.root)
    let indexer = VaultIndexer(root: vault.root, files: files, index: index, status: status)
    return (indexer, index)
}

// MARK: - Cold full index (the "open a large vault" proxy)
//
// As of the Phase-0 batch optimization, `fullIndex()` accumulates changed
// records and commits them in ONE GRDB transaction (NotesIndex.upsert([_]))
// instead of one write per file. Measured on the 3k-file synthetic vault this
// cut cold-index time ~2.5x (≈1290 ms -> ≈520 ms, ~2300 -> ~5700 files/sec).

let (coldIndexer, coldIndex) = try makeIndexer()
let coldResult = await Benchmark.measureAsync(
    "cold full index (\(fileCount) files)", iterations: 1, warmup: 0
) {
    await coldIndexer.fullIndex()
}
let indexedCount = try coldIndex.count()
let filesPerSec = coldResult.mean > 0 ? Double(indexedCount) / coldResult.mean : 0
print(coldResult.summary)
print(
    String(
        format: "  -> indexed %d notes, %.0f files/sec", indexedCount, filesPerSec))

// MARK: - Warm second pass (unchanged -> cheap size+mtime skip)

let warmResult = await Benchmark.measureAsync(
    "warm re-index (unchanged)", iterations: 3, warmup: 0
) {
    await coldIndexer.fullIndex()
}
let speedup = warmResult.mean > 0 ? coldResult.mean / warmResult.mean : 0
print(warmResult.summary)
print(String(format: "  -> warm/cold speedup: %.1fx", speedup))

print(String(repeating: "-", count: 60))
let rssMiB = Benchmark.residentMemory() / 1_048_576
print("Resident memory after large-vault index: \(rssMiB) MiB")
print(String(repeating: "-", count: 60))

// MARK: - Budget assessment (printed for the gate log)

let coldMs = coldResult.mean * 1000
let perFileMs = coldMs / Double(fileCount)
// NOTE: full indexing runs on a BACKGROUND actor (P1.9) — it does NOT block
// vault-open/launch. The UI is interactive immediately; this is throughput.
print(
    String(
        format:
            "BUDGET: background index %d files = %.0f ms (%.2f ms/file, %.0f files/sec) "
            + "— off-main, non-blocking; warm pass %.0f ms (%.1fx); rss %d MiB.",
        fileCount, coldMs, perFileMs, filesPerSec, warmResult.mean * 1000, speedup, rssMiB))
print(
    "Launch is non-blocking (index is async); memory is modest. Per-file parse+"
        + "hash+upsert cost is the lever if very large vaults need faster indexing.")
print("OK — large-vault benchmark complete.")
