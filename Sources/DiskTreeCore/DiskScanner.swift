import Foundation

/// Walks a directory tree measuring allocated (on-disk) bytes and classifying as it goes.
public final class DiskScanner: @unchecked Sendable {
    /// Items smaller than this are merged into one "small items" leaf per kind.
    public let minSize: Int64
    private let lock = NSLock()
    private var _files = 0
    private var _bytes: Int64 = 0
    private var _cancelled = false
    private var _current = ""

    public init(minSize: Int64 = 1 << 20) { self.minSize = minSize }

    public var progress: (files: Int, bytes: Int64) { lock.withLock { (_files, _bytes) } }
    /// Directory most recently opened – shows where a scan is stuck behind a macOS privacy prompt.
    public var current: String { lock.withLock { _current } }
    public func cancel() { lock.withLock { _cancelled = true } }
    var cancelled: Bool { lock.withLock { _cancelled } }

    static let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isVolumeKey,
                                         .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .contentModificationDateKey]
    /// Firmlinked or separately mounted trees that would double-count when scanning `/`.
    static let skipPaths: Set<String> = ["/System/Volumes", "/Volumes", "/dev", "/private/var/vm", "/cores"]

    public func scan(_ url: URL) -> Node {
        let path = url.standardizedFileURL.path
        return scanDirectory(path: path, siblings: [], inheritedKind: nil, inheritedReclaim: nil, depth: 0)
    }

    /// Re-lists one directory, scanning only subdirectories not in `request.skip`. Safe off the main thread:
    /// touches no existing nodes. Pass the result to `Node.install`.
    public func rescan(_ request: RescanRequest) -> Node {
        let parent = (request.path as NSString).deletingLastPathComponent
        let siblings = request.isRoot ? [] : Set(list(parent).map(\.name))
        return scanDirectory(path: request.path, siblings: siblings, inheritedKind: request.inheritedKind,
                             inheritedReclaim: request.inheritedReclaim, depth: request.isRoot ? 0 : 1, skip: request.skip)
    }

    /// Synchronous rescan + install, for callers that own the tree on the current thread.
    @discardableResult
    public func applyRescan(of node: Node, deep: Bool) -> Node {
        let request = node.rescanRequest(deep: deep)
        return node.install(rescan(request), reusing: request.skip)
    }

    private struct Entry {
        let name: String
        let isDirectory: Bool
        let size: Int64
        let modified: Date
    }

    private func list(_ path: String) -> [Entry] {
        lock.withLock { _current = path }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        guard let urls = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: Self.keys) else { return [] }
        return urls.compactMap { u in
            guard let v = try? u.resourceValues(forKeys: Set(Self.keys)), v.isSymbolicLink != true else { return nil }
            let dir = v.isDirectory == true
            if dir, v.isVolume == true || Self.skipPaths.contains(u.path) { return nil }
            return Entry(name: u.lastPathComponent, isDirectory: dir,
                         size: Int64(dir ? 0 : (v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)),
                         modified: v.contentModificationDate ?? .distantPast)
        }
    }

    private func scanDirectory(path: String, siblings: Set<String>, inheritedKind: Kind?, inheritedReclaim: Reclaim?, depth: Int,
                               skip: Set<String> = []) -> Node {
        let entries = cancelled ? [] : list(path)
        let names = Set(entries.map(\.name))
        var own = Classifier.classifyDirectory(path: path, siblings: siblings, children: names)
        // Inside something reclaimable, only another reclaim rule may re-label (e.g. `.bun` under `node_modules` stays deps).
        if inheritedReclaim != nil, own.reclaim == nil { own = .init() }
        let kind = own.kind ?? inheritedKind
        let reclaim = own.reclaim ?? inheritedReclaim

        var children: [Node] = []
        var fileBytes: Int64 = 0
        for e in entries where !e.isDirectory {
            let c = Classifier.classifyFile(name: e.name)
            fileBytes += e.size
            children.append(Node(name: e.name, isDirectory: false, size: e.size, fileCount: 1, modified: e.modified,
                                 kind: kind ?? c.kind ?? .other, reclaim: reclaim ?? c.reclaim))
        }
        lock.withLock { _files += children.count; _bytes += fileBytes }

        let dirs = entries.filter { $0.isDirectory && !skip.contains($0.name) }
        var sub = [Node?](repeating: nil, count: dirs.count)
        let scanChild = { (i: Int) -> Node in
            let d = dirs[i]
            return self.scanDirectory(path: path == "/" ? "/" + d.name : path + "/" + d.name, siblings: names,
                                      inheritedKind: kind, inheritedReclaim: reclaim, depth: depth + 1)
        }
        if depth < 3, dirs.count > 1 {
            // ponytail: fan out only near the root; deep trees stay serial per branch, which already saturates the disk.
            let results = UnsafeMutableBufferPointer<Node?>.allocate(capacity: dirs.count)
            results.initialize(repeating: nil)
            DispatchQueue.concurrentPerform(iterations: dirs.count) { i in results[i] = scanChild(i) }
            sub = Array(results)
            results.deallocate()
        } else {
            for i in dirs.indices { sub[i] = scanChild(i) }
        }
        children += sub.compactMap { $0 }

        let node = Node.directory(name: depth == 0 ? path : (path as NSString).lastPathComponent,
                                  children: mergeSmall(children), kind: kind, reclaim: reclaim)
        if !skip.isEmpty { node.existingNames = names }
        return node
    }

    /// Keeps big items; folds the rest into one aggregate leaf per (kind, reclaim).
    private func mergeSmall(_ nodes: [Node]) -> [Node] {
        var keep: [Node] = []
        var buckets: [String: [Node]] = [:]
        for n in nodes {
            if n.size >= minSize { keep.append(n) } else { buckets["\(n.kind.rawValue)|\(n.reclaim?.reason ?? "")", default: []].append(n) }
        }
        for group in buckets.values {
            let size = group.reduce(0) { $0 + $1.size }
            guard size > 0 else { continue }
            if group.count == 1 && group[0].children.isEmpty { keep.append(group[0]); continue }
            let files = group.reduce(0) { $0 + $1.fileCount }
            keep.append(Node(name: "\(files) small item\(files == 1 ? "" : "s")", isDirectory: false, isAggregate: true,
                             size: size, fileCount: files, modified: group.map(\.modified).max() ?? .distantPast,
                             kind: group[0].kind, reclaim: group[0].reclaim))
        }
        return keep
    }
}
