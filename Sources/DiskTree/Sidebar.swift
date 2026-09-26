import DiskTreeCore
import SwiftUI

struct Sidebar: View {
    @Bindable var model: Model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let n = model.selection ?? model.root { SelectionSection(model: model, node: n) }
                if let s = model.summary, let root = model.root {
                    TypeSection(model: model, summary: s, total: root.size)
                    ReclaimSection(model: model, summary: s)
                }
                if let d = model.disk { DiskSection(disk: d) }
            }
            .padding(20)
        }
        .scrollIndicators(.never)
        .frame(width: 340)
        .background(Theme.panel)
    }
}

struct SectionTitle: View {
    let title: String
    var trailing: String?
    var color = Theme.muted
    var body: some View {
        HStack {
            Text(title.uppercased()).font(Theme.ui(11, .semibold)).kerning(1.2).foregroundStyle(Theme.muted)
            Spacer()
            if let trailing { Text(trailing).font(Theme.num(12, .semibold)).foregroundStyle(color) }
        }
    }
}

struct Bar: View {
    let fraction: Double
    let color: Color
    var height: CGFloat = 4
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.line)
                Capsule().fill(color).frame(width: max(2, g.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: height)
    }
}

struct SelectionSection: View {
    let model: Model
    let node: Node

    var body: some View {
        let total = model.root?.size ?? 1
        let (value, unit) = Fmt.split(node.size)
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Selection")
            HStack(spacing: 10) {
                Rectangle().fill(Theme.color(node.kind)).frame(width: 3, height: 26)
                Text(node.displayName).font(Theme.ui(22, .medium)).foregroundStyle(Theme.text).lineLimit(1).truncationMode(.middle)
            }
            Text(model.relativePath(node)).font(Theme.ui(11)).foregroundStyle(Theme.muted).lineLimit(2).truncationMode(.middle)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value).font(Theme.num(54, .regular)).foregroundStyle(Theme.text)
                Text(unit).font(Theme.ui(20)).foregroundStyle(Theme.muted)
            }
            Bar(fraction: Double(node.size) / Double(max(total, 1)), color: Theme.color(node.kind), height: 5)
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
                GridRow {
                    Stat(label: "Of scan", value: Fmt.percent(node.size, total))
                    Stat(label: "Files", value: Fmt.count(node.fileCount))
                }
                GridRow {
                    Stat(label: "Last write", value: Fmt.ago(node.modified))
                    Stat(label: "Kind", value: node.kind.rawValue)
                }
            }
            if let r = node.reclaim { ReclaimBadge(reclaim: r) }
            if node.parent != nil {
                HStack {
                    Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([node.url]) }
                        .disabled(node.isAggregate)
                    Button("Move to Trash…") { confirmTrash(model, node) }
                        .disabled(!model.canTrash(node))
                }
                .controlSize(.small)
                .font(Theme.ui(12, .medium))
            }
        }
    }
}

struct Stat: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased()).font(Theme.ui(10, .semibold)).kerning(1).foregroundStyle(Theme.muted)
            Text(value).font(Theme.num(16)).foregroundStyle(Theme.text).lineLimit(1)
        }
    }
}

struct ReclaimBadge: View {
    let reclaim: Reclaim
    var body: some View {
        let c = reclaim.tier == .safe ? Theme.safe : Theme.review
        HStack(alignment: .top, spacing: 8) {
            Text(reclaim.tier == .safe ? "SAFE" : "REVIEW").font(Theme.ui(10, .bold)).kerning(1)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(c.opacity(0.18), in: RoundedRectangle(cornerRadius: 3)).foregroundStyle(c)
            Text(reclaim.reason).font(Theme.ui(12)).foregroundStyle(Theme.text)
        }
    }
}

struct TypeSection: View {
    let model: Model
    let summary: Summary
    let total: Int64

    var body: some View {
        let rows = summary.byKind.filter { $0.value > 0 }.sorted { $0.value > $1.value }
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "By type")
            GeometryReader { g in
                HStack(spacing: 1) {
                    ForEach(rows, id: \.key) { k, v in
                        Rectangle().fill(Theme.color(k))
                            .frame(width: max(1, g.size.width * CGFloat(v) / CGFloat(max(total, 1)) - 1))
                    }
                }
            }
            .frame(height: 8).clipShape(RoundedRectangle(cornerRadius: 2))
            ForEach(rows, id: \.key) { k, v in
                Button { model.highlight = model.highlight == k ? nil : k } label: {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2).fill(Theme.color(k)).frame(width: 10, height: 10)
                        Text(k.rawValue).font(Theme.ui(13, .medium)).foregroundStyle(Theme.text)
                        Spacer()
                        Text(Fmt.percent(v, total)).font(Theme.num(12)).foregroundStyle(Theme.muted)
                        Text(Fmt.bytes(v)).font(Theme.num(13)).foregroundStyle(Theme.text).frame(width: 74, alignment: .trailing)
                    }
                    .padding(.vertical, 2).padding(.horizontal, 4)
                    .background(model.highlight == k ? Theme.line : .clear, in: RoundedRectangle(cornerRadius: 4))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct ReclaimSection: View {
    let model: Model
    let summary: Summary

    var body: some View {
        let top = Array(summary.candidates.prefix(12))
        let biggest = Double(top.first?.size ?? 1)
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Reclaimable", trailing: Fmt.bytes(summary.safeBytes + summary.reviewBytes), color: Theme.accent)
            HStack(spacing: 16) {
                Legend(color: Theme.safe, label: "Safe", value: summary.safeBytes)
                Legend(color: Theme.review, label: "Worth a look", value: summary.reviewBytes)
            }
            ForEach(top) { n in
                let c = n.reclaim?.tier == .safe ? Theme.safe : Theme.review
                Button { model.reveal(n) } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Rectangle().fill(c).frame(width: 2)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(model.relativePath(n)).font(Theme.ui(13, .medium)).foregroundStyle(Theme.text)
                                    .lineLimit(1).truncationMode(.middle)
                                Spacer(minLength: 8)
                                Text(Fmt.bytes(n.size)).font(Theme.num(13)).foregroundStyle(Theme.text)
                            }
                            Text(n.reclaim?.reason ?? "").font(Theme.ui(11)).foregroundStyle(Theme.muted).lineLimit(1)
                            Bar(fraction: Double(n.size) / biggest, color: c.opacity(0.8), height: 3)
                        }
                    }
                    .padding(.vertical, 2)
                    .background(model.selection === n ? Theme.line.opacity(0.6) : .clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu { NodeActions(model: model, node: n) }
            }
        }
    }
}

struct Legend: View {
    let color: Color
    let label: String
    let value: Int64
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(Theme.ui(12)).foregroundStyle(Theme.muted)
            Text(Fmt.bytes(value)).font(Theme.num(12, .semibold)).foregroundStyle(Theme.text)
        }
    }
}

struct DiskSection: View {
    let disk: (name: String, free: Int64, total: Int64)
    var body: some View {
        let (value, unit) = Fmt.split(disk.free)
        let used = disk.total - disk.free
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(title: "Disk  \(disk.name)")
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value).font(Theme.num(34, .regular)).foregroundStyle(Theme.text)
                Text("\(unit) free").font(Theme.ui(15)).foregroundStyle(Theme.muted)
            }
            Bar(fraction: Double(used) / Double(max(disk.total, 1)), color: Theme.muted, height: 6)
            HStack {
                Text("\(Fmt.bytes(used)) used")
                Spacer()
                Text("\(Fmt.bytes(disk.total)) total")
            }
            .font(Theme.num(12)).foregroundStyle(Theme.muted)
        }
    }
}
