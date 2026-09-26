import DiskTreeCore
import SwiftUI

enum Theme {
    static let bg = Color(hex: 0x111419)
    static let panel = Color(hex: 0x171B22)
    static let line = Color(hex: 0x262C36)
    static let text = Color(hex: 0xDDE2EA)
    static let muted = Color(hex: 0x7D8696)
    static let accent = Color(hex: 0xE8A33D)
    static let safe = Color(hex: 0x5FBF7A)
    static let review = Color(hex: 0xE8A33D)

    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("Avenir Next", size: size).weight(weight)
    }
    static func num(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .custom("Avenir Next", size: size).weight(weight).monospacedDigit()
    }

    static func color(_ kind: Kind) -> Color {
        switch kind {
        case .code: Color(hex: 0x5B7FC7)
        case .agentScratch: Color(hex: 0xD0834A)
        case .toolchains: Color(hex: 0x4FAE6A)
        case .synced: Color(hex: 0x3FA7B5)
        case .git: Color(hex: 0xD2506A)
        case .media: Color(hex: 0x9A63D8)
        case .documents: Color(hex: 0x9AA1AD)
        case .cache: Color(hex: 0xD4B04A)
        case .apps: Color(hex: 0xD86FA4)
        case .system: Color(hex: 0x6F7F99)
        case .trash: Color(hex: 0xA0664F)
        case .other: Color(hex: 0x58606D)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

enum Fmt {
    static let bytesFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    static func bytes(_ b: Int64) -> String { bytesFormatter.string(fromByteCount: b) }

    /// ("881.2", "GB") for big-number displays.
    static func split(_ b: Int64) -> (String, String) {
        let parts = bytes(b).split(separator: " ", maxSplits: 1).map(String.init)
        return (parts.first ?? "", parts.count > 1 ? parts[1] : "")
    }

    static func count(_ n: Int) -> String {
        switch n {
        case 1_000_000...: String(format: "%.1fM", Double(n) / 1e6)
        case 10_000...: String(format: "%.0fk", Double(n) / 1e3)
        case 1_000...: String(format: "%.1fk", Double(n) / 1e3)
        default: "\(n)"
        }
    }

    static func ago(_ d: Date) -> String {
        guard d > .distantPast else { return "–" }
        return RelativeDateTimeFormatter().localizedString(for: d, relativeTo: .now)
    }

    static func percent(_ part: Int64, _ whole: Int64) -> String {
        guard whole > 0 else { return "–" }
        let p = Double(part) / Double(whole) * 100
        return p >= 10 || p == 0 ? String(format: "%.0f%%", p) : String(format: "%.1f%%", p)
    }
}
