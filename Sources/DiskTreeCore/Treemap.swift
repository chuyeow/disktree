import CoreGraphics

public struct Tile {
    public let node: Node
    public let rect: CGRect
    public let depth: Int
    /// Drawn as a box with a header strip and its children inside.
    public let isContainer: Bool
}

public enum Treemap {
    public static let header: CGFloat = 18
    static let pad: CGFloat = 2

    /// Squarified treemap (Bruls et al.). `sizes` must be sorted descending; returns one rect per size.
    public static func squarify(_ sizes: [Double], in bounds: CGRect) -> [CGRect] {
        let total = sizes.reduce(0, +)
        guard total > 0, bounds.width > 0, bounds.height > 0 else { return sizes.map { _ in .zero } }
        let scale = Double(bounds.width * bounds.height) / total
        let areas = sizes.map { $0 * scale }
        var rects: [CGRect] = []
        var rest = bounds
        var i = 0
        while i < areas.count {
            let side = Double(min(rest.width, rest.height))
            var row = [areas[i]]
            var j = i + 1
            while j < areas.count, worst(row + [areas[j]], side) <= worst(row, side) {
                row.append(areas[j]); j += 1
            }
            let rowArea = row.reduce(0, +)
            if rest.width >= rest.height {
                let w = CGFloat(rowArea / Double(rest.height))
                var y = rest.minY
                for a in row {
                    let h = CGFloat(a) / w
                    rects.append(CGRect(x: rest.minX, y: y, width: w, height: h)); y += h
                }
                rest = CGRect(x: rest.minX + w, y: rest.minY, width: max(0, rest.width - w), height: rest.height)
            } else {
                let h = CGFloat(rowArea / Double(rest.width))
                var x = rest.minX
                for a in row {
                    let w = CGFloat(a) / h
                    rects.append(CGRect(x: x, y: rest.minY, width: w, height: h)); x += w
                }
                rest = CGRect(x: rest.minX, y: rest.minY + h, width: rest.width, height: max(0, rest.height - h))
            }
            i = j
        }
        return rects
    }

    static func worst(_ row: [Double], _ side: Double) -> Double {
        let s = row.reduce(0, +)
        guard let mx = row.max(), let mn = row.min(), s > 0, mn > 0 else { return .infinity }
        return max(side * side * mx / (s * s), s * s / (side * side * mn))
    }

    /// Nested layout: directories become containers until they get too small to read.
    public static func layout(root: Node, in bounds: CGRect, maxDepth: Int = 8) -> [Tile] {
        var tiles: [Tile] = []
        func place(_ node: Node, _ rect: CGRect, _ depth: Int) {
            let canNest = node.isDirectory && !node.children.isEmpty && depth < maxDepth
                && rect.width > 36 && rect.height > header + 16
            tiles.append(Tile(node: node, rect: rect, depth: depth, isContainer: canNest))
            guard canNest else { return }
            let inner = CGRect(x: rect.minX + pad, y: rect.minY + header,
                               width: rect.width - 2 * pad, height: rect.height - header - pad)
            let kids = node.children.filter { $0.size > 0 }
            let rects = squarify(kids.map { Double($0.size) }, in: inner)
            for (k, r) in zip(kids, rects) where r.width >= 2 && r.height >= 2 {
                place(k, r.insetBy(dx: 1, dy: 1), depth + 1)
            }
        }
        place(root, bounds, 0)
        return tiles
    }
}
