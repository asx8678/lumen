//
//  AutosaveScheduler.swift
//  LumenCore
//
//  A small, testable debouncer for autosave (P1.11). It coalesces rapid edits
//  into a single save after a quiescence interval, and supports an immediate
//  `flush` (write-on-blur / tab-switch / app-background / close). The sleep is
//  injectable so the debounce/flush behavior can be unit-tested.
//

import Foundation

/// Debounces a save action: `schedule()` (re)starts the timer; `flush()` runs
/// the action immediately; `cancel()` drops any pending save.
@MainActor
public final class AutosaveScheduler {
    private let interval: Duration
    private let sleep: @Sendable (Duration) async throws -> Void
    private let action: () async -> Void
    private var task: Task<Void, Never>?

    /// - Parameters:
    ///   - interval: Quiescence delay before an autosave fires.
    ///   - sleep: Suspension primitive (injectable for tests).
    ///   - action: The save to perform (should no-op when not dirty).
    public init(
        interval: Duration = .milliseconds(600),
        sleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        },
        action: @escaping () async -> Void
    ) {
        self.interval = interval
        self.sleep = sleep
        self.action = action
    }

    /// Whether a debounced save is currently pending.
    public var isPending: Bool { task != nil }

    /// (Re)starts the debounce timer; cancels any prior pending save.
    public func schedule() {
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.sleep(self.interval)
            } catch {
                return  // cancelled during the wait
            }
            if Task.isCancelled { return }
            self.task = nil
            await self.action()
        }
    }

    /// Cancels any pending debounce and runs the save immediately.
    public func flush() async {
        task?.cancel()
        task = nil
        await action()
    }

    /// Cancels any pending save without running it.
    public func cancel() {
        task?.cancel()
        task = nil
    }
}
