import DiskTreeCore
import SwiftUI

struct TreemapView: View {
    @Bindable var model: Model

    var body: some View {
        GeometryReader { geo in
            let tiles = model.tiles(in: geo.size)
            Canvas { ctx, _ in
                for t in tiles { draw(t, in: &ctx) }
                if let h = model.hover, let t = tiles.last(where: { $0.node === h }) {
                    ctx.stroke(Path(t.rect), with: .color(.white.opacity(0.75)), lineWidth: 1.5)
                }
                if let s = model.selection, let t = tiles.last(where: { $0.node === s }), s !== model.focus {
                    ctx.stroke(Path(t.rect.insetBy(dx: -0.5, dy: -0.5)), with: .color(Theme.accent), lineWidth: 2)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let p): model.hover = hit(tiles, p)
                case .ended: model.hover = nil
                }
            }
            .onTapGesture(count: 2) { p in if let n = hit(tiles, p) { model.zoom(to: n) } }
            .onTapGesture { p in model.selection = hit(tiles, p) }
            .contextMenu { if let n = model.hover { NodeActions(model: model, node: n) } }
            .help(model.hover.map { "\(model.relativePath($0))\n\(Fmt.bytes($0.size))\($0.reclaim.map { " · " + $0.reason } ?? "")" } ?? "")
        }
        .background(Theme.bg)
    }

    func hit(_ tiles: [Tile], _ p: CGPoint) -> Node? {
        tiles.last { $0.rect.contains(p) }?.node
    }

    func draw(_ t: Tile, in ctx: inout GraphicsContext) {
        let base = Theme.color(t.node.kind)
        let dim = model.highlight.map { $0 != t.node.kind } ?? false
        var c = ctx
        c.opacity = dim ? 0.22 : 1
        let r = t.rect
        let path = Path(r)
        if t.isContainer {
            c.fill(path, with: .color(base.opacity(0.13)))
            let head = CGRect(x: r.minX, y: r.minY, width: r.width, height: Treemap.header)
            c.fill(Path(head), with: .color(base.opacity(0.22)))
            c.fill(Path(CGRect(x: r.minX, y: r.minY, width: r.width, height: 2)), with: .color(base.opacity(0.9)))
            label(&c, t.node.displayName, Fmt.bytes(t.node.size), in: head.insetBy(dx: 6, dy: 0), bold: true)
        } else {
            c.fill(path, with: .color(base.opacity(t.node.isAggregate ? 0.2 : 0.34)))
            if t.node.reclaim != nil { hatch(&c, r) }
            if r.width > 54, r.height > 34 {
                let inner = r.insetBy(dx: 6, dy: 4)
                label(&c, t.node.displayName, nil, in: CGRect(x: inner.minX, y: inner.minY, width: inner.width, height: 15), bold: false)
                label(&c, nil, Fmt.bytes(t.node.size), in: CGRect(x: inner.minX, y: inner.minY + 15, width: inner.width, height: 14), bold: false)
            }
        }
        c.stroke(path, with: .color(Theme.bg.opacity(0.9)), lineWidth: 1)
    }

    func hatch(_ ctx: inout GraphicsContext, _ r: CGRect) {
        var c = ctx
        c.clip(to: Path(r))
        var p = Path()
        var x = r.minX - r.height
        while x < r.maxX {
            p.move(to: CGPoint(x: x, y: r.maxY))
            p.addLine(to: CGPoint(x: x + r.height, y: r.minY))
            x += 6
        }
        c.stroke(p, with: .color(.white.opacity(0.11)), lineWidth: 1)
    }

    /// Name left, size after it; clipped rather than wrapped.
    func label(_ ctx: inout GraphicsContext, _ name: String?, _ size: String?, in r: CGRect, bold: Bool) {
        guard r.width > 24 else { return }
        var c = ctx
        c.clip(to: Path(r))
        var x = r.minX
        if let name {
            let t = c.resolve(Text(name).font(Theme.ui(12, bold ? .semibold : .medium)).foregroundColor(Theme.text))
            c.draw(t, at: CGPoint(x: x, y: r.midY), anchor: .leading)
            x += t.measure(in: CGSize(width: 2000, height: 40)).width + 8
        }
        if let size {
            let t = c.resolve(Text(size).font(Theme.num(11)).foregroundColor(Theme.muted))
            let w = t.measure(in: CGSize(width: 2000, height: 40)).width
            // Header sizes sit right-aligned when there's room; leaf sizes go on their own line.
            let at = name != nil && r.maxX - w > x ? r.maxX - w : x
            c.draw(t, at: CGPoint(x: at, y: r.midY), anchor: .leading)
        }
    }
}

struct NodeActions: View {
    let model: Model
    let node: Node

    var body: some View {
        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([node.url]) }
            .disabled(node.isAggregate)
        if node.isDirectory { Button("Zoom In") { model.zoom(to: node) } }
        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(node.path, forType: .string)
        }
        Divider()
        Button("Move to Trash…") { confirmTrash(model, node) }.disabled(!model.canTrash(node))
    }
}

@MainActor func confirmTrash(_ model: Model, _ node: Node) {
    let a = NSAlert()
    a.messageText = "Move “\(node.displayName)” to the Trash?"
    a.informativeText = "\(Fmt.bytes(node.size)) · \(model.relativePath(node))\n\(node.reclaim?.reason ?? "Not flagged as reclaimable – make sure you don’t need it.")"
    a.alertStyle = node.reclaim?.tier == .safe ? .informational : .warning
    a.addButton(withTitle: "Move to Trash")
    a.addButton(withTitle: "Cancel")
    if a.runModal() == .alertFirstButtonReturn { model.trash(node) }
}
