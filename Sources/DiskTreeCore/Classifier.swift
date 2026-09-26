import Foundation

public struct Classification: Equatable {
    public var kind: Kind?
    public var reclaim: Reclaim?
    public init(_ kind: Kind? = nil, _ reclaim: Reclaim? = nil) { self.kind = kind; self.reclaim = reclaim }
}

/// Pure path rules: what a directory or file is, and whether deleting it is safe.
/// `.safe` = regenerated automatically or by one command. `.review` = usually disposable, but look first.
public enum Classifier {
    static func safe(_ reason: String) -> Reclaim { Reclaim(tier: .safe, reason: reason) }
    static func review(_ reason: String) -> Reclaim { Reclaim(tier: .review, reason: reason) }

    /// Matched against the end of the path, most specific first.
    static let suffixRules: [(String, Classification)] = [
        ("/Library/Developer/Xcode/DerivedData", .init(.cache, safe("Xcode build products"))),
        ("/Library/Developer/Xcode/iOS DeviceSupport", .init(.toolchains, safe("device symbols – re-fetched on connect"))),
        ("/Library/Developer/Xcode/watchOS DeviceSupport", .init(.toolchains, safe("device symbols – re-fetched on connect"))),
        ("/Library/Developer/Xcode/Archives", .init(.toolchains, review("old app archives"))),
        ("/Library/Developer/CoreSimulator/Caches", .init(.cache, safe("simulator caches"))),
        ("/Library/Developer/CoreSimulator/Devices", .init(.toolchains, review("simulators – `xcrun simctl delete unavailable`"))),
        ("/Library/Containers/com.docker.docker", .init(.toolchains, review("Docker images – `docker system prune`"))),
        ("/Library/Application Support/MobileSync/Backup", .init(.other, review("iPhone/iPad backups"))),
        ("/Library/Caches", .init(.cache, safe("app caches – regenerable"))),
        ("/Library/Logs", .init(.system, safe("logs"))),
        ("/Library/Mobile Documents", .init(.synced)),
        ("/Library/CloudStorage", .init(.synced)),
        ("/Library/Developer", .init(.toolchains)),
        ("/Library/Android", .init(.toolchains)),
        ("/Library/pnpm", .init(.cache, safe("pnpm store – `pnpm store prune`"))),
        ("/Library/Mail", .init(.documents)),
        ("/.yarn/cache", .init(.cache, safe("Yarn cache"))),
        ("/.gradle/caches", .init(.cache, safe("Gradle cache"))),
        ("/.m2/repository", .init(.cache, review("Maven repository"))),
        ("/go/pkg/mod", .init(.cache, safe("Go module cache"))),
        ("/.cargo/registry", .init(.cache, safe("Cargo registry cache"))),
        ("/.bun/install/cache", .init(.cache, safe("Bun cache"))),
        ("/.local/share/mise", .init(.toolchains)),
        ("/.local/share/Trash", .init(.trash, safe("in Trash"))),
    ]

    static let nameRules: [String: Classification] = [
        ".Trash": .init(.trash, safe("in Trash – empty from Finder")),
        ".git": .init(.git),
        "node_modules": .init(.code, safe("npm dependencies – reinstallable")),
        ".cache": .init(.cache, safe("regenerable")),
        ".npm": .init(.cache, safe("npm cache")),
        ".pnpm-store": .init(.cache, safe("pnpm store")),
        "DerivedData": .init(.cache, safe("Xcode build products")),
        "__pycache__": .init(.code, safe("Python bytecode")),
        ".pytest_cache": .init(.code, safe("test cache")),
        ".mypy_cache": .init(.code, safe("type-check cache")),
        ".ruff_cache": .init(.code, safe("lint cache")),
        ".next": .init(.code, safe("Next.js build output")),
        ".turbo": .init(.code, safe("Turborepo cache")),
        ".parcel-cache": .init(.code, safe("Parcel cache")),
        ".nuxt": .init(.code, safe("Nuxt build output")),
        ".svelte-kit": .init(.code, safe("SvelteKit build output")),
        ".gradle": .init(.toolchains),
        "worktrees": .init(.agentScratch, review("worktrees – check for unpushed work")),
        ".codex": .init(.agentScratch), ".claude": .init(.agentScratch), ".cursor": .init(.agentScratch),
        ".gemini": .init(.agentScratch), ".aider": .init(.agentScratch), ".herdr": .init(.agentScratch),
        ".rustup": .init(.toolchains), ".cargo": .init(.toolchains), ".pyenv": .init(.toolchains),
        ".nvm": .init(.toolchains), ".volta": .init(.toolchains), ".sdkman": .init(.toolchains),
        ".asdf": .init(.toolchains), ".bun": .init(.toolchains), ".deno": .init(.toolchains),
        ".m2": .init(.toolchains), ".swiftpm": .init(.toolchains), ".platformio": .init(.toolchains),
        ".ollama": .init(.toolchains), ".docker": .init(.toolchains),
        "Dropbox": .init(.synced), "Google Drive": .init(.synced), "OneDrive": .init(.synced), "Sync": .init(.synced),
        "Movies": .init(.media), "Music": .init(.media), "Pictures": .init(.media),
        "Documents": .init(.documents), "Desktop": .init(.documents),
        "Downloads": .init(.documents, review("Downloads – usually re-downloadable")),
        "Applications": .init(.apps),
        "Library": .init(.system),
    ]

    /// Directory names that are build output only when a sibling marks the project type.
    static let buildOutputs: [String: (markers: Set<String>, reason: String)] = [
        "target": (["Cargo.toml", "pom.xml"], "build output – rebuilt on next build"),
        ".build": (["Package.swift"], "SwiftPM build – rebuilt on next build"),
        "build": (["package.json", "build.gradle", "build.gradle.kts", "CMakeLists.txt", "setup.py", "pyproject.toml"], "build output – rebuilt on next build"),
        "dist": (["package.json", "setup.py", "pyproject.toml"], "build output – rebuilt on next build"),
        ".venv": (["pyproject.toml", "requirements.txt", "setup.py", "uv.lock"], "virtualenv – recreatable"),
        "venv": (["pyproject.toml", "requirements.txt", "setup.py", "uv.lock"], "virtualenv – recreatable"),
        "Pods": (["Podfile"], "CocoaPods – `pod install`"),
        "vendor": (["Gemfile", "go.mod"], "vendored deps – reinstallable"),
    ]

    static let projectMarkers: Set<String> = [".git", "package.json", "Cargo.toml", "Package.swift", "go.mod", "pyproject.toml", "Gemfile"]

    public static func classifyDirectory(path: String, siblings: Set<String>, children: Set<String>) -> Classification {
        let name = (path as NSString).lastPathComponent
        if let (_, c) = suffixRules.first(where: { path.hasSuffix($0.0) }) { return c }
        if let b = buildOutputs[name], !b.markers.isDisjoint(with: siblings) { return .init(.code, safe(b.reason)) }
        if let c = nameRules[name] { return c }
        if name.hasSuffix(".app") { return .init(.apps) }
        if !projectMarkers.isDisjoint(with: children) { return .init(.code) }
        return .init()
    }

    static let extKinds: [String: Kind] = {
        var m: [String: Kind] = [:]
        for e in ["mp4", "mov", "mkv", "avi", "m4v", "webm", "jpg", "jpeg", "png", "heic", "gif", "tif", "tiff", "raw",
                  "cr2", "cr3", "nef", "arw", "dng", "mp3", "wav", "flac", "aac", "m4a", "aiff", "psd", "blend", "mts"] { m[e] = .media }
        for e in ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "key", "pages", "numbers", "txt", "md", "epub",
                  "csv", "rtf", "sketch", "fig"] { m[e] = .documents }
        for e in ["swift", "rs", "go", "py", "js", "ts", "tsx", "jsx", "rb", "java", "kt", "c", "cc", "cpp", "h", "hpp",
                  "m", "cs", "json", "yaml", "yml", "toml", "lock", "o", "a", "rlib", "rmeta", "so", "dylib", "wasm", "pack", "idx"] { m[e] = .code }
        for e in ["vmdk", "qcow2", "vdi", "raw", "img", "gguf", "safetensors", "ckpt"] { m[e] = .toolchains }
        return m
    }()

    public static func classifyFile(name: String) -> Classification {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "dmg", "pkg", "iso", "ipsw", "xip": return .init(.other, review("installer image – re-downloadable"))
        default: return .init(extKinds[ext])
        }
    }
}
