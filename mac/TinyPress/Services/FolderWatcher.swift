import CoreServices
import Foundation

/// Recursive file-system watcher built on top of FSEvents.
///
/// `DispatchSource.makeFileSystemObjectSource` watches a single inode and
/// is unsuitable for whole-tree change detection. FSEvents handles the
/// recursive case and gives us a single coalesced callback per batch of
/// changes — we layer a small async debounce on top so the rebuild
/// pipeline isn't kicked off mid-typing.
final class FolderWatcher: @unchecked Sendable {
    private let url: URL
    private let debounceInterval: TimeInterval
    private let ignoredComponents: Set<String>

    private let queue = DispatchQueue(label: "tinypress.folder-watcher")
    private var stream: FSEventStreamRef?
    private var pendingDebounce: Task<Void, Never>?
    private var onChange: (@MainActor @Sendable () -> Void)?

    /// - Parameters:
    ///   - url: Folder to watch (recursively).
    ///   - debounceInterval: How long to wait after the last change before
    ///     calling `onChange`.
    ///   - ignoredComponents: Path components inside the tree that should
    ///     not trigger rebuilds. Defaults to common build / VCS dirs and
    ///     the rendered output folders.
    init(
        url: URL,
        debounceInterval: TimeInterval = 0.3,
        ignoredComponents: Set<String> = [
            ".git", ".DS_Store", "node_modules", "_site", "output", ".build",
        ]
    ) {
        self.url = url
        self.debounceInterval = debounceInterval
        self.ignoredComponents = ignoredComponents
    }

    deinit {
        stopInternal()
    }

    /// Begin watching. `onChange` runs on the main actor every time the
    /// debounce window expires after at least one non-ignored change.
    @MainActor
    func start(onChange: @MainActor @Sendable @escaping () -> Void) throws {
        queue.sync {
            self.onChange = onChange
        }
        try startStream()
    }

    /// Stop watching. Safe to call multiple times.
    func stop() {
        stopInternal()
    }

    // MARK: FSEvents wiring

    private func startStream() throws {
        let resolved = url.resolvingSymlinksInPath().path
        let info = Unmanaged.passUnretained(self).toOpaque()
        var context = FSEventStreamContext(
            version: 0,
            info: info,
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = {
            _, info, numEvents, eventPaths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            // With `kFSEventStreamCreateFlagUseCFTypes` set, `eventPaths` is
            // a `CFArray` of `CFString`, not a `char**`.
            let cfArray = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue()
            var paths: [String] = []
            paths.reserveCapacity(numEvents)
            for index in 0..<numEvents {
                if let raw = CFArrayGetValueAtIndex(cfArray, index) {
                    let cfString = Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue()
                    paths.append(cfString as String)
                }
            }
            watcher.handleEvents(paths: paths)
        }

        let flags = UInt32(
            kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagNoDefer
                | kFSEventStreamCreateFlagUseCFTypes
        )

        guard
            let stream = FSEventStreamCreate(
                kCFAllocatorDefault,
                callback,
                &context,
                [resolved] as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                0.05,
                flags
            )
        else {
            throw FolderWatcherError.streamCreationFailed
        }

        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    private func stopInternal() {
        queue.sync {
            if let stream {
                FSEventStreamStop(stream)
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
                self.stream = nil
            }
            pendingDebounce?.cancel()
            pendingDebounce = nil
            onChange = nil
        }
    }

    // MARK: Event handling

    private func handleEvents(paths: [String]) {
        // Filter out paths that live inside an ignored folder. We treat
        // any component-level match as "ignored" so output folders, the
        // git directory, etc. don't loop us back into a rebuild.
        let interesting = paths.contains { path in
            let components = (path as NSString).pathComponents
            for component in components where ignoredComponents.contains(component) {
                return false
            }
            return true
        }
        guard interesting else { return }
        scheduleDebouncedFire()
    }

    private func scheduleDebouncedFire() {
        queue.async {
            self.pendingDebounce?.cancel()
            let interval = self.debounceInterval
            let onChange = self.onChange
            self.pendingDebounce = Task { @MainActor [interval, onChange] in
                let nanos = UInt64(interval * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
                if Task.isCancelled { return }
                onChange?()
            }
        }
    }
}

enum FolderWatcherError: Error {
    case streamCreationFailed
}
