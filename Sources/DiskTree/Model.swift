import AppKit
import DiskTreeCore
import Observation

@MainActor @Observable
final class Model {
    var root: Node?
    var summary: Summary?
    var focus: Node?
    var selection: Node?
    var hover: Node?
    var highlight: Kind?
    var scanURL = FileManager.default.homeDirectoryForCurrentUser
    var scanning = false
    var progress: (files: Int, bytes: Int64) = (0, 0)
    var currentPath = ""
    var scanSeconds: Double = 0
    var disk: (name: String, free: Int64, total: Int64)?
    /// Bumped whenever the tree mutates, so derived views recompute.
    var version = 0

    @ObservationIgnored private var scanner: DiskScanner?
    @ObservationIgnored private var tileCache: (key: String, tiles: [Tile])?

    func scan(_ url: URL? = nil) {
        if let url { scanURL = url }
        scanner?.cancel()
        let s = DiskScanner()
        scanner = s
        scanning = true
        progress = (0, 0)
        let target = scanURL
        let start = Date()
        Task {
            let poll = Task { @MainActor in
                while !Task.isCancelled {
                    progress = s.progress
                    currentPath = s.current
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
            // Without this, App Nap throttles the scan ~50x whenever the window is in the background.
            let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "Scanning disk")
            let tree = await Task.detached(priority: .userInitiated) { s.scan(target) }.value
            ProcessInfo.processInfo.endActivity(activity)
            poll.cancel()
            guard scanner === s else { return }
            install(tree, seconds: Date().timeIntervalSince(start))
            captureIfRequested()
        }
    }

    /// `--capture out.png`: writes the live window to a PNG after the scan, for verification without screen-recording access.
    private func captureIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--capture"), i + 1 < args.count else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            if let sel = args.firstIndex(of: "--select").flatMap({ Int(args[$0 + 1]) }),
               let n = summary?.candidates.dropFirst(sel).first { reveal(n) }
            try? await Task.sleep(for: .seconds(1))
            guard let v = NSApp.windows.first(where: \.isVisible)?.contentView,
                  let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
            v.cacheDisplay(in: v.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[i + 1]))
        }
    }

    func cancelScan() {
        scanner?.cancel()
    }

    func install(_ tree: Node, seconds: Double) {
        root = tree
        focus = tree
        selection = tree
        scanSeconds = seconds
        scanning = false
        refresh()
        let v = try? tree.url.resourceValues(forKeys: [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        if let v, let total = v.volumeTotalCapacity {
            disk = (v.volumeName ?? "Disk", v.volumeAvailableCapacityForImportantUsage ?? 0, Int64(total))
        }
    }

    func refresh() {
        summary = root.map(Summary.init)
        version += 1
        tileCache = nil
    }

    func tiles(in size: CGSize) -> [Tile] {
        guard let focus else { return [] }
        let key = "\(ObjectIdentifier(focus).hashValue)|\(size.width)x\(size.height)|\(version)"
        if let c = tileCache, c.key == key { return c.tiles }
        let t = Treemap.layout(root: focus, in: CGRect(origin: .zero, size: size))
        tileCache = (key, t)
        return t
    }

    func zoom(to node: Node) {
        focus = node.isDirectory && !node.children.isEmpty ? node : (node.ancestors.last ?? node)
    }

    func zoomOut() {
        if let p = focus?.ancestors.last { focus = p }
    }

    /// Selects a node and zooms so it is on screen.
    func reveal(_ node: Node) {
        selection = node
        if let focus, !(node.ancestors.contains { $0 === focus }) || node === focus {
            self.focus = node.ancestors.last ?? node
        }
    }

    func canTrash(_ node: Node) -> Bool {
        node.parent != nil && !node.isAggregate && !node.path.contains("/.Trash")
    }

    func trash(_ node: Node) {
        guard canTrash(node) else { return }
        NSWorkspace.shared.recycle([node.url]) { _, error in
            Task { @MainActor in
                if let error {
                    NSAlert(error: error).runModal()
                    return
                }
                if let f = self.focus, f === node || f.ancestors.contains(where: { $0 === node }) {
                    self.focus = node.ancestors.last
                }
                if self.selection === node { self.selection = node.ancestors.last }
                node.removeFromParent()
                self.refresh()
                self.updateDisk()
            }
        }
    }

    private func updateDisk() {
        guard let d = disk, let v = try? scanURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]) else { return }
        disk = (d.name, v.volumeAvailableCapacityForImportantUsage ?? d.free, d.total)
    }

    func relativePath(_ node: Node) -> String {
        guard let root else { return node.path }
        if node === root { return (root.path as NSString).abbreviatingWithTildeInPath }
        return String(node.path.dropFirst(root.path.count + 1))
    }
}
