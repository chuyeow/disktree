import Foundation

public enum Kind: String, CaseIterable, Sendable {
    case code = "Code"
    case agentScratch = "Agent scratch"
    case toolchains = "Toolchains"
    case synced = "Synced"
    case git = "Git"
    case media = "Media"
    case documents = "Documents"
    case cache = "Cache"
    case apps = "Apps"
    case system = "System"
    case trash = "Trash"
    case other = "Other"
}

public struct Reclaim: Hashable, Sendable {
    public enum Tier: Sendable { case safe, review }
    public let tier: Tier
    public let reason: String
    public init(tier: Tier, reason: String) { self.tier = tier; self.reason = reason }
}

/// One file or directory in the scanned tree. Small items are merged into
/// aggregate leaves (`isAggregate`) so multi-million-file trees stay small in memory.
public final class Node: Identifiable, @unchecked Sendable {
    public let name: String
    public let isDirectory: Bool
    public let isAggregate: Bool
    public private(set) var size: Int64
    public private(set) var fileCount: Int
    public private(set) var modified: Date
    public private(set) var kind: Kind
    public let reclaim: Reclaim?
    /// Kind this directory hands down to its contents (own rule or inherited); nil = contents classify themselves.
    public let passKind: Kind?
    public private(set) var children: [Node] = []
    public private(set) weak var parent: Node?

    public init(name: String, isDirectory: Bool, isAggregate: Bool = false, size: Int64, fileCount: Int,
                modified: Date, kind: Kind, reclaim: Reclaim?, passKind: Kind? = nil, children: [Node] = []) {
        self.name = name
        self.isDirectory = isDirectory
        self.isAggregate = isAggregate
        self.size = size
        self.fileCount = fileCount
        self.modified = modified
        self.kind = kind
        self.reclaim = reclaim
        self.passKind = passKind
        self.children = children.sorted { $0.size > $1.size }
        for c in self.children { c.parent = self }
    }

    /// Directory whose size, count and mtime roll up from its children; kind defaults to the dominant child kind.
    public static func directory(name: String, children: [Node], kind: Kind? = nil, reclaim: Reclaim? = nil) -> Node {
        Node(name: name, isDirectory: true,
             size: children.reduce(0) { $0 + $1.size },
             fileCount: children.reduce(0) { $0 + $1.fileCount },
             modified: children.map(\.modified).max() ?? .distantPast,
             kind: kind ?? dominantKind(children), reclaim: reclaim, passKind: kind, children: children)
    }

    static func dominantKind(_ children: [Node]) -> Kind {
        var totals: [Kind: Int64] = [:]
        for c in children { totals[c.kind, default: 0] += c.size }
        return totals.max { $0.value < $1.value }?.key ?? .other
    }

    /// Root's name is its absolute path.
    public var path: String { parent.map { $0.path + "/" + name } ?? name }
    public var displayName: String { parent == nil ? (name as NSString).lastPathComponent : name }
    public var url: URL { URL(fileURLWithPath: path) }
    public var ancestors: [Node] { parent.map { $0.ancestors + [$0] } ?? [] }

    /// Deepest directory in this tree on the way to `path`.
    public func deepestNode(for path: String) -> Node? {
        guard path == self.path || path.hasPrefix(self.path == "/" ? "/" : self.path + "/") else { return nil }
        var node = self
        for part in path.dropFirst(self.path.count).split(separator: "/") {
            guard let next = node.children.first(where: { $0.isDirectory && !$0.isAggregate && $0.name == part }) else { break }
            node = next
        }
        return node
    }

    /// What a background rescan of this directory needs, captured on the thread that owns the tree.
    /// Shallow rescans skip existing subdirectories; `install` re-attaches them.
    public func rescanRequest(deep: Bool) -> RescanRequest {
        RescanRequest(path: path, isRoot: parent == nil, inheritedKind: parent?.passKind, inheritedReclaim: parent?.reclaim,
                      skip: deep ? [] : Set(children.filter { $0.isDirectory && !$0.isAggregate }.map(\.name)))
    }

    /// Swaps this node for a freshly scanned copy: adopts the reused subdirectories that still exist, then
    /// fixes ancestor totals. Returns the node now in the tree.
    @discardableResult
    public func install(_ fresh: Node, reusing skip: Set<String>) -> Node {
        let reused = children.filter { skip.contains($0.name) && fresh.existingNames.contains($0.name) }
        if !reused.isEmpty {
            for n in reused { n.parent = fresh }
            fresh.children = (fresh.children + reused).sorted { $0.size > $1.size }
            fresh.size += reused.reduce(0) { $0 + $1.size }
            fresh.fileCount += reused.reduce(0) { $0 + $1.fileCount }
            fresh.modified = max(fresh.modified, reused.map(\.modified).max() ?? .distantPast)
            if fresh.passKind == nil { fresh.kind = Node.dominantKind(fresh.children) }
        }
        guard let p = parent, let i = p.children.firstIndex(where: { $0 === self }) else { return fresh }
        let dSize = fresh.size - size, dCount = fresh.fileCount - fileCount
        p.children[i] = fresh
        p.children.sort { $0.size > $1.size }
        fresh.parent = p
        parent = nil
        var a: Node? = p
        while let n = a {
            n.size += dSize
            n.fileCount += dCount
            a = n.parent
        }
        return fresh
    }

    /// Names of the directory's entries at scan time; set only on rescanned directories.
    var existingNames: Set<String> = []

    public func removeFromParent() {
        guard let p = parent else { return }
        p.children.removeAll { $0 === self }
        var a: Node? = p
        while let n = a {
            n.size -= size
            n.fileCount -= fileCount
            a = n.parent
        }
        parent = nil
    }

    public func forEach(_ body: (Node) -> Void) {
        body(self)
        for c in children { c.forEach(body) }
    }
}

public struct RescanRequest: Sendable {
    public let path: String
    public let isRoot: Bool
    public let inheritedKind: Kind?
    public let inheritedReclaim: Reclaim?
    public let skip: Set<String>
}

public struct Summary {
    public var byKind: [Kind: Int64] = [:]
    public var safeBytes: Int64 = 0
    public var reviewBytes: Int64 = 0
    public var dirCount = 0
    /// Top-most reclaimable nodes, largest first.
    public var candidates: [Node] = []

    public init(root: Node) {
        var candidates: [Node] = []
        root.forEach { n in
            if n.isDirectory { dirCount += 1 }
            if n.children.isEmpty {
                byKind[n.kind, default: 0] += n.size
                switch n.reclaim?.tier {
                case .safe: safeBytes += n.size
                case .review: reviewBytes += n.size
                case nil: break
                }
            }
            if n.reclaim != nil, n.parent?.reclaim == nil, !n.isAggregate { candidates.append(n) }
        }
        self.candidates = candidates.sorted { $0.size > $1.size }
    }
}
