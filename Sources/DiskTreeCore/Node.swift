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
    public let modified: Date
    public let kind: Kind
    public let reclaim: Reclaim?
    public private(set) var children: [Node] = []
    public private(set) weak var parent: Node?

    public init(name: String, isDirectory: Bool, isAggregate: Bool = false, size: Int64, fileCount: Int,
                modified: Date, kind: Kind, reclaim: Reclaim?, children: [Node] = []) {
        self.name = name
        self.isDirectory = isDirectory
        self.isAggregate = isAggregate
        self.size = size
        self.fileCount = fileCount
        self.modified = modified
        self.kind = kind
        self.reclaim = reclaim
        self.children = children.sorted { $0.size > $1.size }
        for c in self.children { c.parent = self }
    }

    /// Directory whose size, count and mtime roll up from its children; kind defaults to the dominant child kind.
    public static func directory(name: String, children: [Node], kind: Kind? = nil, reclaim: Reclaim? = nil) -> Node {
        Node(name: name, isDirectory: true,
             size: children.reduce(0) { $0 + $1.size },
             fileCount: children.reduce(0) { $0 + $1.fileCount },
             modified: children.map(\.modified).max() ?? .distantPast,
             kind: kind ?? dominantKind(children), reclaim: reclaim, children: children)
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
