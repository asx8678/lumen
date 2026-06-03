//
//  VaultWatcher.swift
//  LumenCore
//
//  Recursively watches the open vault directory for filesystem changes via
//  FSEvents (P1.6), coalesces bursts, and broadcasts batches of changed URLs to
//  any number of subscribers as `AsyncStream`s.
//
//  Consumers (the app's reconciliation in P1.6, the indexing actor in P1.9)
//  call `events()` to get their own stream. FSEvents fires on a private
//  dispatch queue; callbacks hop to the main actor before coalescing/emitting.
//

import Foundation

#if canImport(CoreServices)
import CoreServices
#endif

/// Watches a vault root recursively and broadcasts coalesced change batches.
@MainActor
public final class VaultWatcher {
    /// The watched vault root.
    public let root: URL

    private let latency: TimeInterval
    private var stream: FSEventStreamRef?
    private var coalescer: ChangeCoalescer!
    private var continuations: [UUID: AsyncStream<Set<URL>>.Continuation] = [:]

    /// - Parameters:
    ///   - root: The vault root to watch recursively.
    ///   - debounce: Quiescence window for coalescing bursts.
    ///   - latency: FSEvents coalescing latency (seconds).
    public init(root: URL, debounce: Duration = .milliseconds(250), latency: TimeInterval = 0.1) {
        self.root = root
        self.latency = latency
        self.coalescer = ChangeCoalescer(interval: debounce) { [weak self] batch in
            self?.broadcast(batch)
        }
    }

    // Note: callers must invoke `stop()` (tied to vault close / app teardown);
    // the FSEvents stream is a non-Sendable resource that must be released on
    // the main actor, so it is not torn down from a nonisolated `deinit`.

    /// Returns a new change stream. Each subscriber gets its own stream; all
    /// receive every coalesced batch. The stream ends when the watcher stops.
    public func events() -> AsyncStream<Set<URL>> {
        AsyncStream { continuation in
            let id = UUID()
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.continuations[id] = nil }
            }
        }
    }

    // MARK: - Lifecycle

    /// Starts watching. Safe to call once; no-op if already running.
    public func start() {
        guard stream == nil else { return }
        let info = Unmanaged.passUnretained(self).toOpaque()
        var context = FSEventStreamContext(
            version: 0, info: info, retain: nil, release: nil, copyDescription: nil)
        let paths = [root.path] as CFArray
        let flags = UInt32(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer
                | kFSEventStreamCreateFlagUseCFTypes)
        guard
            let stream = FSEventStreamCreate(
                kCFAllocatorDefault,
                eventCallback,
                &context,
                paths,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                latency,
                flags)
        else { return }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
        FSEventStreamStart(stream)
    }

    /// Stops watching and finishes all subscriber streams.
    public func stop() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
        for continuation in continuations.values { continuation.finish() }
        continuations.removeAll()
    }

    // MARK: - Internal plumbing

    /// Called (on a background queue) by the C callback; hops to main.
    nonisolated fileprivate func ingest(_ paths: [String]) {
        let urls = paths.map { URL(fileURLWithPath: $0) }
        Task { @MainActor [weak self] in
            self?.coalescer.record(urls)
        }
    }

    private func broadcast(_ batch: Set<URL>) {
        for continuation in continuations.values {
            continuation.yield(batch)
        }
    }
}

/// FSEvents C callback. `info` carries an unretained pointer to the watcher.
private func eventCallback(
    streamRef: ConstFSEventStreamRef,
    clientCallBackInfo: UnsafeMutableRawPointer?,
    numEvents: Int,
    eventPaths: UnsafeMutableRawPointer,
    eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let clientCallBackInfo else { return }
    let watcher = Unmanaged<VaultWatcher>.fromOpaque(clientCallBackInfo).takeUnretainedValue()
    let paths: [String]
    if let cfArray = unsafeBitCast(eventPaths, to: CFArray.self) as? [String] {
        paths = cfArray
    } else {
        paths = []
    }
    watcher.ingest(paths)
}
