import CoreServices
import Foundation

/// File-system change notifications for a directory tree (FSEvents).
public enum DirectoryEvents {
    /// One batch of changes.
    public struct Batch: Sendable, Equatable {
        /// Paths of the files that changed.
        public var paths: [String]
        /// Whether the system dropped events, so the paths are incomplete and the tree should be rescanned.
        public var needsRescan: Bool
    }

    /// Returns the files that change under `directory`, in batches. Ending the consumer stops the watch.
    public static func stream(for directory: URL, latency: TimeInterval = 0.2) -> AsyncStream<Batch> {
        AsyncStream { continuation in
            let queue = DispatchQueue(label: "app.broom.directory-events")
            let box = Unmanaged.passRetained(ContinuationBox(continuation))
            var context = FSEventStreamContext(version: 0, info: box.toOpaque(), retain: nil, release: nil, copyDescription: nil)
            let flags = kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer

            guard let stream = FSEventStreamCreate(
                nil,
                { _, info, count, paths, flags, _ in
                    guard let info else { return }
                    let box = Unmanaged<ContinuationBox>.fromOpaque(info).takeUnretainedValue()
                    let paths = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []
                    let dropped = UnsafeBufferPointer(start: flags, count: count).contains { $0 & DirectoryEvents.droppedFlags != 0 }
                    box.continuation.yield(Batch(paths: paths, needsRescan: dropped))
                },
                &context,
                [directory.path] as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                latency,
                FSEventStreamCreateFlags(flags)
            ) else {
                box.release()
                continuation.finish()
                return
            }

            FSEventStreamSetDispatchQueue(stream, queue)
            FSEventStreamStart(stream)

            // Safe to send: after this point the stream is only touched once, by the teardown below.
            nonisolated(unsafe) let watch = stream
            continuation.onTermination = { _ in
                // Tear down on the callback queue so no callback is still using the box when it is released.
                queue.async {
                    FSEventStreamStop(watch)
                    FSEventStreamInvalidate(watch)
                    FSEventStreamRelease(watch)
                    box.release()
                }
            }
        }
    }

    /// Flags that mean individual file events were coalesced or lost.
    private static let droppedFlags = FSEventStreamEventFlags(
        kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped
    )

    private final class ContinuationBox: Sendable {
        let continuation: AsyncStream<Batch>.Continuation

        init(_ continuation: AsyncStream<Batch>.Continuation) {
            self.continuation = continuation
        }
    }
}
