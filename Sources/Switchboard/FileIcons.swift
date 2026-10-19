import SwiftUI

/// File icon themes for the folder tree, Source Control and editor tabs, after VS Code's: Seti (its default,
/// colored glyphs per language) and Material Icon Theme (colored folders and file symbols).
enum IconTheme: String, CaseIterable, Identifiable {
    case minimal, seti, material
    var id: String { rawValue }
    var title: String {
        switch self {
        case .minimal: "Minimal"
        case .seti: "Seti"
        case .material: "Material"
        }
    }
}

/// What a file is drawn with: a short glyph ("TS", "{}") or an SF Symbol, in the language's color.
struct FileGlyph: Equatable {
    var text: String? = nil
    var symbol: String? = nil
    let color: UInt32

    /// By exact file name first (README.md, Package.swift, Dockerfile), then by extension.
    static func of(_ name: String) -> FileGlyph {
        let lower = name.lowercased()
        if let g = names[lower] { return g }
        if lower.hasPrefix("readme") { return FileGlyph(symbol: "book.closed.fill", color: blue) }
        if lower.hasPrefix("license") || lower.hasPrefix("licence") { return FileGlyph(symbol: "checkmark.seal.fill", color: yellow) }
        if lower.hasPrefix(".env") { return FileGlyph(symbol: "key.fill", color: yellow) }
        if lower.hasPrefix("dockerfile") { return FileGlyph(symbol: "shippingbox.fill", color: blue) }
        let ext = (lower as NSString).pathExtension
        return extensions[ext] ?? FileGlyph(symbol: "doc", color: gray)
    }

    // the Seti palette
    static let blue: UInt32 = 0x519ABA, yellow: UInt32 = 0xCBCB41, orange: UInt32 = 0xE37933, red: UInt32 = 0xCC3E44
    static let green: UInt32 = 0x8DC149, purple: UInt32 = 0xA074C4, pink: UInt32 = 0xF55385, gray: UInt32 = 0x8A8A8A
    static let swiftOrange: UInt32 = 0xF05138, gitOrange: UInt32 = 0xF14E32

    static let names: [String: FileGlyph] = [
        "package.swift": FileGlyph(symbol: "swift", color: swiftOrange),
        "package.json": FileGlyph(text: "npm", color: red),
        "package-lock.json": FileGlyph(symbol: "lock.fill", color: gray),
        "package.resolved": FileGlyph(symbol: "lock.fill", color: gray),
        "yarn.lock": FileGlyph(symbol: "lock.fill", color: gray),
        "pnpm-lock.yaml": FileGlyph(symbol: "lock.fill", color: gray),
        "cargo.lock": FileGlyph(symbol: "lock.fill", color: gray),
        "podfile.lock": FileGlyph(symbol: "lock.fill", color: gray),
        "gemfile.lock": FileGlyph(symbol: "lock.fill", color: gray),
        ".gitignore": FileGlyph(symbol: "arrow.triangle.branch", color: gitOrange),
        ".gitattributes": FileGlyph(symbol: "arrow.triangle.branch", color: gitOrange),
        ".gitmodules": FileGlyph(symbol: "arrow.triangle.branch", color: gitOrange),
        "makefile": FileGlyph(symbol: "hammer.fill", color: orange),
        "claude.md": FileGlyph(symbol: "sparkle", color: 0xD97757),
        "agents.md": FileGlyph(symbol: "sparkle", color: 0xD97757),
        "tsconfig.json": FileGlyph(text: "TS", color: blue),
        ".editorconfig": FileGlyph(symbol: "gearshape.fill", color: gray),
    ]

    static let extensions: [String: FileGlyph] = {
        var m: [String: FileGlyph] = [:]
        func add(_ exts: [String], _ g: FileGlyph) { for e in exts { m[e] = g } }
        add(["swift"], FileGlyph(symbol: "swift", color: swiftOrange))
        add(["js", "mjs", "cjs"], FileGlyph(text: "JS", color: yellow))
        add(["ts", "mts", "cts"], FileGlyph(text: "TS", color: blue))
        add(["jsx", "tsx"], FileGlyph(symbol: "atom", color: blue))
        add(["json", "jsonc", "json5"], FileGlyph(text: "{}", color: yellow))
        add(["md", "markdown", "mdx"], FileGlyph(text: "M↓", color: blue))
        add(["py", "pyi"], FileGlyph(text: "Py", color: blue))
        add(["go"], FileGlyph(text: "GO", color: blue))
        add(["rs"], FileGlyph(text: "RS", color: 0xDEA584))
        add(["rb", "erb"], FileGlyph(text: "RB", color: red))
        add(["java", "class", "jar"], FileGlyph(text: "J", color: red))
        add(["kt", "kts"], FileGlyph(text: "K", color: purple))
        add(["c", "h"], FileGlyph(text: "C", color: blue))
        add(["cpp", "cc", "hpp", "cxx"], FileGlyph(text: "C++", color: blue))
        add(["m", "mm"], FileGlyph(text: "M", color: blue))
        add(["cs"], FileGlyph(text: "C#", color: green))
        add(["php"], FileGlyph(text: "php", color: purple))
        add(["dart"], FileGlyph(text: "D", color: blue))
        add(["lua"], FileGlyph(text: "lua", color: blue))
        add(["vue"], FileGlyph(text: "V", color: green))
        add(["svelte"], FileGlyph(text: "S", color: orange))
        add(["sh", "bash", "zsh", "fish"], FileGlyph(symbol: "terminal.fill", color: green))
        add(["html", "htm"], FileGlyph(text: "<>", color: orange))
        add(["css"], FileGlyph(text: "#", color: blue))
        add(["scss", "sass", "less"], FileGlyph(text: "#", color: pink))
        add(["yaml", "yml"], FileGlyph(text: "Y", color: purple))
        add(["toml", "ini", "cfg", "conf", "properties"], FileGlyph(symbol: "gearshape.fill", color: gray))
        add(["xml", "plist", "xib", "storyboard"], FileGlyph(text: "<>", color: orange))
        add(["sql", "sqlite", "db"], FileGlyph(symbol: "cylinder.fill", color: pink))
        add(["png", "jpg", "jpeg", "gif", "heic", "webp", "bmp", "tiff", "ico", "icns"], FileGlyph(symbol: "photo.fill", color: purple))
        add(["svg"], FileGlyph(symbol: "photo.fill", color: yellow))
        add(["pdf"], FileGlyph(symbol: "doc.richtext.fill", color: red))
        add(["zip", "gz", "tar", "tgz", "xz", "7z", "dmg"], FileGlyph(symbol: "doc.zipper", color: gray))
        add(["txt", "log"], FileGlyph(symbol: "doc.text", color: gray))
        add(["csv", "tsv", "xlsx"], FileGlyph(symbol: "tablecells.fill", color: green))
        add(["lock"], FileGlyph(symbol: "lock.fill", color: gray))
        add(["mp3", "wav", "m4a", "aiff"], FileGlyph(symbol: "waveform", color: purple))
        add(["mp4", "mov", "m4v", "webm"], FileGlyph(symbol: "film.fill", color: purple))
        add(["ttf", "otf", "woff", "woff2"], FileGlyph(symbol: "textformat", color: red))
        add(["metal", "glsl", "wgsl"], FileGlyph(text: "◆", color: green))
        add(["env"], FileGlyph(symbol: "key.fill", color: yellow))
        return m
    }()

    /// Material Icon Theme's folder colors by name; nil = its default blue-grey folder.
    static func folderColor(_ name: String) -> UInt32? {
        switch name.lowercased() {
        case "src", "sources", "source", "lib", "app", "apps", "packages": 0x4CAF50
        case "test", "tests", "__tests__", "spec", "specs", "e2e": 0x00BFA5
        case "scripts", "bin", "tools": 0xFFCA28
        case "docs", "doc", "documentation": 0x42A5F5
        case "assets", "images", "img", "icons", "resources", "public", "static", "media": 0x26A69A
        case "components", "views", "ui", "pages": 0xFFA726
        case ".git", ".github", ".gitlab": 0xF4511E
        case "node_modules", "vendor", "pods", ".build", "build", "dist", "out", "target", "deriveddata": 0x8D6E63
        case "config", "configs", ".vscode", ".idea", "settings", ".claude": 0x7E57C2
        case "api", "server", "backend": 0xEF5350
        default: nil
        }
    }
}

/// The icon of a file or folder in the chosen icon theme.
struct FileIconView: View {
    @AppStorage("iconTheme") private var theme: IconTheme = .seti
    let name: String
    var isDir = false
    var expanded = false

    var body: some View {
        Group {
            switch theme {
            case .minimal: minimal
            case .seti: isDir ? AnyView(setiFolder) : AnyView(glyph(FileGlyph.of(name)))
            case .material: isDir ? AnyView(materialFolder) : AnyView(glyph(FileGlyph.of(name), symbolsOnly: true))
            }
        }
        .frame(width: 16, height: 14)
    }

    private var minimal: some View {
        Image(systemName: isDir ? (expanded ? "folder.fill" : "folder") : minimalSymbol)
            .foregroundStyle(isDir ? Color.accentColor : .secondary)
    }

    /// Seti draws folders without color: the chevron says it all
    private var setiFolder: some View {
        Image(systemName: expanded ? "folder.fill" : "folder").foregroundStyle(.secondary).font(.system(size: 12))
    }

    private var materialFolder: some View {
        Image(systemName: expanded ? "folder.fill" : "folder.fill")
            .foregroundStyle(Color(hex: FileGlyph.folderColor(name) ?? 0x90A4AE))
            .opacity(expanded ? 1 : 0.9)
            .font(.system(size: 12))
    }

    @ViewBuilder
    private func glyph(_ g: FileGlyph, symbolsOnly: Bool = false) -> some View {
        if let text = g.text, !symbolsOnly {
            Text(text)
                .font(.system(size: text.count > 2 ? 7 : 8.5, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(hex: g.color))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        } else if let text = g.text {
            // Material: a page with the language's letters on it
            ZStack {
                Image(systemName: "doc.fill").font(.system(size: 13)).foregroundStyle(Color(hex: g.color))
                Text(text).font(.system(size: 5.5, weight: .black, design: .rounded)).foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.5).padding(.top, 3).frame(width: 10)
            }
        } else {
            Image(systemName: g.symbol ?? "doc").font(.system(size: 11)).foregroundStyle(Color(hex: g.color))
        }
    }

    private var minimalSymbol: String {
        switch (name as NSString).pathExtension.lowercased() {
        case "swift", "js", "ts", "tsx", "jsx", "py", "go", "rs", "rb", "java", "kt", "c", "h", "m", "cpp", "cs", "sh":
            "chevron.left.forwardslash.chevron.right"
        case "md", "markdown", "txt": "doc.text"
        case "json", "yaml", "yml", "toml", "plist", "xml": "curlybraces"
        case "png", "jpg", "jpeg", "gif", "heic", "webp", "svg", "icns": "photo"
        case "pdf": "doc.richtext"
        case "zip", "gz", "tar": "doc.zipper"
        default: "doc"
        }
    }
}
