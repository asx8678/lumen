//
//  ChangeCoalescer.swift
//  LumenCore
//
//  Debounces/coalesces bursts of filesystem-change URLs into a single batch
//  emitted after a quiescence window (P1.6). FSEvents tends to fire many events
//  for one logical edit; this collapses them. The sleep is injectable so the
//  coalescing behavior is unit-testable.
//

import Foundation

/// Accumulates changed URLs and emits a coalesced batch after quiescence.
@MainActor
public final class ChangeCoalescer {
    private let interval: Duration
    private let sleep: @Sendable (Duration) async throws -> Void
    private let emit: (Set<URL>) -> Void
    private var pending: Set<URL> = []
    private var task: Task<Void, Never>?

    /// - Parameters:
    ///   - interval: Quiescence window before a batch is emitted.
    ///   - sleep: Suspension primitive (injectable for tests).
    ///   - emit: Called once per coalesced batch (on the main actor).
    public init(
        interval: Duration = .milliseconds(250),
        sleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        },
        emit: @escaping (Set<URL>) -> Void
    ) {
        self.interval = interval
        self.sleep = sleep
        self.emit = emit
    }

    /// Records changed URLs and (re)starts the debounce timer.
    public func record(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        pending.formUnion(urls)
        schedule()
    }

    /// Emits the pending batch immediately (if any).
    public func flush() {
        task?.cancel()
        task = nil
        deliver()
    }

    private func schedule() {
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            do { try await self.sleep(self.interval) } catch { return }
            if Task.isCancelled { return }
            self.task = nil
            self.deliver()
        }
    }

    private func deliver() {
        guard !pending.isEmpty else { return }
        let batch = pending
        pending = []
        emit(batch)
    }
}
