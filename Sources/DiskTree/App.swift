import AppKit
import DiskTreeCore
import SwiftUI

@main
struct DiskTreeApp: App {
    @State private var model = Model()

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        Window("DiskTree", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 960, minHeight: 600)
                .onAppear {
                    NSApp.activate()
                    if model.root == nil && !model.scanning {
                        let args = CommandLine.arguments
                        let root = args.firstIndex(of: "--root").flatMap { $0 + 1 < args.count ? URL(fileURLWithPath: args[$0 + 1]) : nil }
                        model.scan(root)
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Scan Folder…") { chooseFolder(model) }.keyboardShortcut("o")
                Button("Rescan") { model.scan() }.keyboardShortcut("r")
            }
            CommandMenu("View") {
                Button("Zoom Out") { model.zoomOut() }.keyboardShortcut(.upArrow, modifiers: .command)
                Button("Zoom to Top") { model.focus = model.root }.keyboardShortcut(.upArrow, modifiers: [.command, .shift])
            }
        }
    }
}

@MainActor func chooseFolder(_ model: Model) {
    let p = NSOpenPanel()
    p.canChooseDirectories = true
    p.canChooseFiles = false
    p.directoryURL = model.scanURL
    p.prompt = "Scan"
    if p.runModal() == .OK, let url = p.url { model.scan(url) }
}

struct ContentView: View {
    @Bindable var model: Model

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                TopBar(model: model)
                ZStack {
                    TreemapView(model: model).padding(10)
                    if model.scanning { ScanningView(model: model) }
                }
            }
            Rectangle().fill(Theme.line).frame(width: 1)
            Sidebar(model: model)
        }
        .background(Theme.bg)
        .foregroundStyle(Theme.text)
        .preferredColorScheme(.dark)
        .ignoresSafeArea()
    }
}

struct TopBar: View {
    @Bindable var model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                if let root = model.root {
                    Text(Fmt.bytes(root.size)).font(Theme.num(14, .semibold))
                    Text("\(Fmt.count(root.fileCount)) files · \(Fmt.count(model.summary?.dirCount ?? 0)) dirs · \(String(format: "%.1fs", model.scanSeconds))")
                        .font(Theme.num(12)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Button { chooseFolder(model) } label: { Label("Scan Folder…", systemImage: "folder") }
                Button { model.scan() } label: { Label("Rescan", systemImage: "arrow.clockwise") }
                    .disabled(model.scanning)
            }
            .buttonStyle(.borderless).font(Theme.ui(12, .medium))
            HStack(spacing: 0) {
                Breadcrumbs(model: model)
                Spacer(minLength: 16)
                KindLegend(model: model)
            }
        }
        .padding(.leading, 84).padding(.trailing, 14).padding(.top, 10).padding(.bottom, 2)
    }
}

struct Breadcrumbs: View {
    @Bindable var model: Model
    var body: some View {
        HStack(spacing: 4) {
            if let f = model.focus {
                ForEach(Array((f.ancestors + [f]).enumerated()), id: \.offset) { i, n in
                    if i > 0 { Text("›").foregroundStyle(Theme.muted) }
                    Button(n.parent == nil ? (n.path as NSString).abbreviatingWithTildeInPath : n.name) { model.focus = n }
                        .buttonStyle(.plain)
                        .foregroundStyle(n === f ? Theme.text : Theme.muted)
                }
            }
        }
        .font(Theme.ui(13, .medium)).lineLimit(1)
    }
}

struct KindLegend: View {
    @Bindable var model: Model
    var body: some View {
        let kinds = (model.summary?.byKind ?? [:]).filter { $0.value > 0 }.sorted { $0.value > $1.value }.map(\.key)
        HStack(spacing: 12) {
            HStack(spacing: 5) {
                Canvas { c, s in
                    c.fill(Path(CGRect(origin: .zero, size: s)), with: .color(Theme.muted.opacity(0.35)))
                    var p = Path()
                    for x in stride(from: -s.height, to: s.width, by: 3) {
                        p.move(to: CGPoint(x: x, y: s.height)); p.addLine(to: CGPoint(x: x + s.height, y: 0))
                    }
                    c.stroke(p, with: .color(.white.opacity(0.5)), lineWidth: 0.7)
                }
                .frame(width: 10, height: 10)
                Text("Reclaimable")
            }
            ForEach(kinds, id: \.self) { k in
                Button { model.highlight = model.highlight == k ? nil : k } label: {
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2).fill(Theme.color(k)).frame(width: 10, height: 10)
                        Text(k.rawValue)
                    }
                    .opacity(model.highlight == nil || model.highlight == k ? 1 : 0.4)
                }
                .buttonStyle(.plain)
            }
        }
        .font(Theme.ui(12, .medium)).foregroundStyle(Theme.muted).lineLimit(1)
    }
}

struct ScanningView: View {
    let model: Model
    var body: some View {
        VStack(spacing: 10) {
            ProgressView().controlSize(.large)
            Text("Scanning \((model.scanURL.path as NSString).abbreviatingWithTildeInPath)").font(Theme.ui(15, .medium))
            Text("\(Fmt.count(model.progress.files)) files · \(Fmt.bytes(model.progress.bytes))")
                .font(Theme.num(13)).foregroundStyle(Theme.muted)
            Text((model.currentPath as NSString).abbreviatingWithTildeInPath)
                .font(Theme.ui(11)).foregroundStyle(Theme.muted).lineLimit(1).truncationMode(.middle).frame(maxWidth: 420)
            Text("Stalled? macOS may be showing a privacy prompt. Grant Full Disk Access to skip them.")
                .font(Theme.ui(11)).foregroundStyle(Theme.muted)
            HStack {
                Button("Open Full Disk Access Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                }
                Button("Cancel") { model.cancelScan() }
            }
            .controlSize(.small)
        }
        .padding(28)
        .background(Theme.panel.opacity(0.95), in: RoundedRectangle(cornerRadius: 10))
    }
}
