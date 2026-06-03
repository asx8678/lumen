//
//  Benchmark.swift
//  LumenBenchmark
//
//  Standardized measurement helpers so benchmarks report consistent numbers
//  (wall-clock timing + a cheap resident-memory sample).
//

import Foundation

#if canImport(Darwin)
import Darwin
#endif

/// The result of running a benchmark: timing statistics over N iterations.
public struct BenchmarkResult: Sendable {
    /// A human-readable name for the benchmark.
    public let name: String
    /// Number of measured iterations.
    public let iterations: Int
    /// Per-iteration durations, in seconds.
    public let samples: [Double]
    /// Resident memory footprint sampled after the run, in bytes (0 if unknown).
    public let residentBytes: UInt64

    /// Mean duration in seconds.
    public var mean: Double { samples.isEmpty ? 0 : samples.reduce(0, +) / Double(samples.count) }
    /// Smallest measured duration in seconds.
    public var min: Double { samples.min() ?? 0 }
    /// Largest measured duration in seconds.
    public var max: Double { samples.max() ?? 0 }

    /// A single-line, CI-friendly summary.
    public var summary: String {
        let mem = residentBytes > 0 ? ", rss \(residentBytes / 1_048_576) MiB" : ""
        return String(
            format: "%@: mean %.3f ms, min %.3f ms, max %.3f ms (x%d%@)",
            name, mean * 1000, min * 1000, max * 1000, iterations, mem
        )
    }
}

/// A tiny, dependency-free benchmark runner.
public enum Benchmark {
    /// Runs `body` `iterations` times (after `warmup` unmeasured runs) and
    /// returns timing statistics.
    ///
    /// - Parameters:
    ///   - name: Label for the result.
    ///   - iterations: Number of measured iterations (clamped to >= 1).
    ///   - warmup: Number of unmeasured warmup iterations.
    ///   - body: The work to measure.
    /// - Returns: A ``BenchmarkResult``.
    @discardableResult
    public static func measure(
        _ name: String,
        iterations: Int = 5,
        warmup: Int = 1,
        _ body: () throws -> Void
    ) rethrows -> BenchmarkResult {
        for _ in 0..<Swift.max(0, warmup) {
            try body()
        }
        let count = Swift.max(1, iterations)
        var samples: [Double] = []
        samples.reserveCapacity(count)
        for _ in 0..<count {
            let start = DispatchTime.now().uptimeNanoseconds
            try body()
            let end = DispatchTime.now().uptimeNanoseconds
            samples.append(Double(end - start) / 1_000_000_000)
        }
        return BenchmarkResult(
            name: name,
            iterations: count,
            samples: samples,
            residentBytes: residentMemory()
        )
    }

    /// Async variant of ``measure(_:iterations:warmup:_:)`` for awaiting work
    /// (e.g. the actor-based indexing pipeline).
    @discardableResult
    public static func measureAsync(
        _ name: String,
        iterations: Int = 5,
        warmup: Int = 1,
        _ body: () async throws -> Void
    ) async rethrows -> BenchmarkResult {
        for _ in 0..<Swift.max(0, warmup) {
            try await body()
        }
        let count = Swift.max(1, iterations)
        var samples: [Double] = []
        samples.reserveCapacity(count)
        for _ in 0..<count {
            let start = DispatchTime.now().uptimeNanoseconds
            try await body()
            let end = DispatchTime.now().uptimeNanoseconds
            samples.append(Double(end - start) / 1_000_000_000)
        }
        return BenchmarkResult(
            name: name,
            iterations: count,
            samples: samples,
            residentBytes: residentMemory()
        )
    }

    /// Samples the current process's resident memory footprint in bytes.
    /// Returns 0 when unavailable.
    public static func residentMemory() -> UInt64 {
        #if canImport(Darwin)
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
        #else
        return 0
        #endif
    }
}
