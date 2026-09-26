import CoreGraphics
import Foundation
import Testing
@testable import DiskTreeCore

@Suite struct ClassifierTests {
    func dir(_ path: String, siblings: Set<String> = [], children: Set<String> = []) -> Classification {
        Classifier.classifyDirectory(path: path, siblings: siblings, children: children)
    }

    @Test func cachesAreSafe() {
        let c = dir("/Users/a/Library/Caches")
        #expect(c.kind == .cache)
        #expect(c.reclaim?.tier == .safe)
        #expect(dir("/Users/a/.cache").reclaim?.tier == .safe)
    }

    @Test func rustTargetNeedsCargoSibling() {
        #expect(dir("/Users/a/src/x/target", siblings: ["Cargo.toml", "src"]).reclaim?.tier == .safe)
        #expect(dir("/Users/a/src/x/target", siblings: ["notes.md"]).reclaim == nil)
    }

    @Test func nodeModulesAndGit() {
        #expect(dir("/Users/a/src/x/node_modules").reclaim?.tier == .safe)
        let g = dir("/Users/a/src/x/.git")
        #expect(g.kind == .git)
        #expect(g.reclaim == nil)
    }

    @Test func projectDirIsCode() {
        #expect(dir("/Users/a/src/x", children: [".git", "README.md"]).kind == .code)
    }

    @Test func worktreesNeedReview() {
        let c = dir("/Users/a/.codex/worktrees")
        #expect(c.kind == .agentScratch)
        #expect(c.reclaim?.tier == .review)
    }

    @Test func syncedAndToolchains() {
        #expect(dir("/Users/a/Library/Mobile Documents").kind == .synced)
        #expect(dir("/Users/a/.rustup").kind == .toolchains)
        #expect(dir("/Users/a/Library/Developer/Xcode/DerivedData").reclaim?.tier == .safe)
    }

    @Test func fileKindsByExtension() {
        #expect(Classifier.classifyFile(name: "clip.MOV").kind == .media)
        #expect(Classifier.classifyFile(name: "paper.pdf").kind == .documents)
        #expect(Classifier.classifyFile(name: "Xcode.dmg").reclaim?.tier == .review)
        #expect(Classifier.classifyFile(name: "Makefile").kind == nil)
    }
}

@Suite struct TreeTests {
    func leaf(_ name: String, _ size: Int64, _ kind: Kind, reclaim: Reclaim? = nil) -> Node {
        Node(name: name, isDirectory: false, size: size, fileCount: 1, modified: .distantPast, kind: kind, reclaim: reclaim)
    }

    @Test func summaryTotalsByKindAndTier() {
        let safe = Reclaim(tier: .safe, reason: "cache")
        let root = Node.directory(name: "/r", children: [
            leaf("a", 100, .code),
            Node.directory(name: "c", children: [leaf("b", 50, .cache, reclaim: safe)], kind: .cache, reclaim: safe),
        ])
        let s = Summary(root: root)
        #expect(root.size == 150)
        #expect(s.byKind[.code] == 100)
        #expect(s.byKind[.cache] == 50)
        #expect(s.safeBytes == 50)
        #expect(s.candidates.map(\.name) == ["c"])
    }

    @Test func removeUpdatesAncestors() {
        let child = leaf("x", 40, .media)
        let mid = Node.directory(name: "m", children: [child, leaf("y", 10, .media)])
        let root = Node.directory(name: "/r", children: [mid, leaf("z", 5, .other)])
        child.removeFromParent()
        #expect(mid.size == 10)
        #expect(root.size == 15)
        #expect(root.fileCount == 2)
    }
}

@Suite struct TreemapTests {
    @Test func squarifyPreservesAreaAndBounds() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)
        let sizes: [Double] = [60, 30, 20, 10, 5, 3, 1]
        let rects = Treemap.squarify(sizes, in: bounds)
        #expect(rects.count == sizes.count)
        let total = sizes.reduce(0, +)
        for (r, s) in zip(rects, sizes) {
            #expect(abs(r.width * r.height - s / total * 120_000) < 1)
            #expect(bounds.insetBy(dx: -0.01, dy: -0.01).contains(r))
        }
        for i in rects.indices {
            for j in rects.indices where j > i {
                let o = rects[i].intersection(rects[j])
                #expect(o.isNull || o.width * o.height < 0.01)
            }
        }
    }

    @Test func layoutNestsChildrenInsideParent() {
        let root = Node.directory(name: "/r", children: [
            Node.directory(name: "a", children: [
                Node(name: "f", isDirectory: false, size: 70, fileCount: 1, modified: .distantPast, kind: .code, reclaim: nil),
                Node(name: "g", isDirectory: false, size: 30, fileCount: 1, modified: .distantPast, kind: .code, reclaim: nil),
            ]),
            Node(name: "b", isDirectory: false, size: 100, fileCount: 1, modified: .distantPast, kind: .media, reclaim: nil),
        ])
        let tiles = Treemap.layout(root: root, in: CGRect(x: 0, y: 0, width: 800, height: 600))
        let a = tiles.first { $0.node.name == "a" }!
        let f = tiles.first { $0.node.name == "f" }!
        #expect(a.isContainer)
        #expect(a.rect.contains(f.rect))
        #expect(f.rect.minY >= a.rect.minY + Treemap.header)
    }
}

@Suite struct ScannerTests {
    @Test func scansAndClassifiesRealTree() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("disktree-\(UUID().uuidString)")
        let proj = root.appendingPathComponent("proj")
        try FileManager.default.createDirectory(at: proj.appendingPathComponent("node_modules/dep"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: proj.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try Data(count: 3_000_000).write(to: proj.appendingPathComponent("node_modules/dep/big.js"))
        try Data(count: 2_000_000).write(to: root.appendingPathComponent("movie.mp4"))
        for i in 0..<5 { try Data(count: 10_000).write(to: proj.appendingPathComponent("f\(i).swift")) }
        defer { try? FileManager.default.removeItem(at: root) }

        let tree = DiskScanner().scan(root)
        let s = Summary(root: tree)
        let p = try #require(tree.children.first { $0.name == "proj" })
        #expect(p.kind == .code)
        #expect(s.candidates.first?.name == "node_modules")
        #expect(s.safeBytes >= 3_000_000)
        #expect(s.byKind[.media, default: 0] >= 2_000_000)
        #expect(p.children.contains { $0.isAggregate && $0.fileCount == 5 })
    }
}

@Suite struct InheritanceTests {
    @Test func toolchainNameInsideReclaimableKeepsParentLabel() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("disktree-\(UUID().uuidString)")
        let bun = root.appendingPathComponent("node_modules/.bun")
        try FileManager.default.createDirectory(at: bun, withIntermediateDirectories: true)
        try Data(count: 2_000_000).write(to: bun.appendingPathComponent("pkg.js"))
        defer { try? FileManager.default.removeItem(at: root) }
        let tree = DiskScanner().scan(root)
        let b = try #require(tree.children.first?.children.first { $0.name == ".bun" })
        #expect(b.kind == .code)
        #expect(b.reclaim?.tier == .safe)
    }
}
