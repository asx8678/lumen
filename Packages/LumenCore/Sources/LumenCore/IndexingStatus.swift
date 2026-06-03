//
//  IndexingStatus.swift
//  LumenCore
//
//  Observable progress state for background indexing (P1.9). The indexing actor
//  updates this on the main actor; the status-bar VIEW that renders it is P1.18.
//

import Observation

/// Main-actor-safe, observable indexing progress.
@MainActor
@Observable
public final class IndexingStatus {
    /// Whether an index pass is currently running.
    public private(set) var isIndexing: Bool = false
    /// Files processed in the current pass.
    public private(set) var processed: Int = 0
    /// Total files to process in the current pass.
    public private(set) var total: Int = 0

    public init() {}

    /// Fraction complete in `0...1` (0 when total is unknown/zero).
    public var fractionComplete: Double {
        total > 0 ? min(1, Double(processed) / Double(total)) : 0
    }

    // MARK: - Mutation (driven by the indexer)

    /// Begins a pass with a known total (resets counters).
    func begin(total: Int) {
        self.isIndexing = true
        self.processed = 0
        self.total = total
    }

    /// Records one processed file.
    func advance() {
        processed += 1
    }

    /// Marks the pass complete.
    func finish() {
        isIndexing = false
        processed = total
    }

    /// Resets to idle (e.g. on vault close).
    public func reset() {
        isIndexing = false
        processed = 0
        total = 0
    }
}
