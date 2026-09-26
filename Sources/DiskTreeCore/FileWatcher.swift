import CoreServices
import Foundation

/// FSEvents on one tree, reported per changed directory. Starting from an earlier event id replays
/// everything that changed since, e.g. while a long scan was running.
public final class FileWatcher: @unchecked Sendable {
    public struct Change: Sendable {
        /// Directory whose entries changed, spelled under the watched path (no trailing slash).
        public let path: String
        /// Events were coalesced or dropped: rescan the whole subtree, not just this directory.
        public let deep: Bool
        /// The watched root itself moved or was deleted.
        public let rootChanged: Bool
    }

    public static var now: FSEventStreamEventId { FSEventsGetCurrentEventId() }

    private var stream: FSEventStreamRef?
    private let handler: @Sendable ([Change]) -> Void
    private let root: String
    private let realRoot: String
    private let queue = DispatchQueue(label: "disktree.fsevents")

    public init(path: String, since: FSEventStreamEventId, latency: TimeInterval = 1,
                handler: @escaping @Sendable ([Change]) -> Void) {
        self.handler = handler
        root = path
        // FSEvents reports resolved paths (/private/var/...); map them back to the caller's spelling.
        if let resolved = realpath(path, nil) {
            realRoot = String(cString: resolved)
            free(resolved)
        } else {
            realRoot = path
        }
        var ctx = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                       retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
            let me = Unmanaged<FileWatcher>.fromOpaque(info!).takeUnretainedValue()
            let list = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
            let rescanSub = UInt32(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped)
            let changes = (0..<count).compactMap { i -> Change? in
                let f = flags[i]
                if f & UInt32(kFSEventStreamEventFlagHistoryDone) != 0 { return nil }
                var p = list[i]
                while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
                if p.hasPrefix(me.realRoot) { p = me.root + p.dropFirst(me.realRoot.count) }
                return Change(path: p, deep: f & rescanSub != 0, rootChanged: f & UInt32(kFSEventStreamEventFlagRootChanged) != 0)
            }
            if !changes.isEmpty { me.handler(changes) }
        }
        let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagWatchRoot)
        guard let s = FSEventStreamCreate(nil, callback, &ctx, [path] as CFArray, since, latency, flags) else { return }
        FSEventStreamSetDispatchQueue(s, queue)
        FSEventStreamStart(s)
        stream = s
    }

    public func stop() {
        guard let s = stream else { return }
        stream = nil
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
    }

    deinit { stop() }
}
