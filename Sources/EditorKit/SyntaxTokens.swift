import Foundation

/// A tiny, language-agnostic highlighter: comments, strings, numbers, keywords, types and function calls,
/// enough for an editor theme to color a file. Works on UTF-16 offsets, so the ranges go straight into an
/// NSTextStorage.
public enum SyntaxTokens {
    public enum Kind: Sendable, CaseIterable {
        case comment, string, number, keyword, type, function
    }

    public struct Token: Equatable, Sendable {
        public let kind: Kind
        public let location: Int
        public let length: Int
    }

    /// Comment syntax of a family of languages.
    public struct Language: Equatable, Sendable {
        public var line: [String]
        public var block: [(open: String, close: String)]
        public var keywords: Set<String>
        /// `'…'` is a string (not a character or a lifetime/apostrophe)
        public var singleQuoteStrings = true
        /// `` `…` `` is a string (JS template literals, Go raw strings, shell)
        public var backtickStrings = false

        public static func == (a: Language, b: Language) -> Bool {
            a.line == b.line && a.keywords == b.keywords && a.block.map(\.open) == b.block.map(\.open)
                && a.block.map(\.close) == b.block.map(\.close)
        }
    }

    /// The highlighter stops at this size: re-coloring on every keystroke has to stay instant.
    public static let maxLength = 300_000

    static let cKeywords: Set<String> = [
        "abstract", "actor", "any", "as", "async", "await", "break", "case", "catch", "class", "const", "continue",
        "default", "defer", "delete", "do", "else", "enum", "export", "extends", "extension", "false", "final",
        "finally", "fn", "for", "func", "function", "get", "go", "guard", "if", "impl", "implements", "import",
        "in", "init", "inout", "instanceof", "interface", "internal", "is", "let", "match", "mod", "module", "mut",
        "namespace", "new", "nil", "null", "open", "operator", "override", "package", "private", "protocol",
        "pub", "public", "repeat", "return", "self", "Self", "set", "some", "static", "struct", "super", "switch",
        "this", "throw", "throws", "trait", "true", "try", "type", "typeof", "undefined", "use", "var", "void",
        "where", "while", "with", "yield", "chan", "map", "range", "select", "fallthrough", "goto", "unsafe",
        "dyn", "loop", "ref", "crate", "char", "int", "long", "short", "float", "double", "bool", "unsigned",
        "signed", "sizeof", "typedef", "union", "volatile", "extern", "auto", "register", "template", "typename",
        "virtual", "friend", "explicit", "mutating", "nonisolated", "weak", "unowned", "lazy", "convenience",
        "required", "fileprivate", "associatedtype", "subscript", "deinit", "rethrows", "of", "from", "declare",
        "readonly", "keyof", "satisfies", "val", "fun", "object", "companion", "data", "sealed", "when", "elif",
    ]

    static let hashKeywords: Set<String> = [
        "and", "as", "assert", "async", "await", "break", "case", "class", "continue", "def", "del", "do", "done",
        "elif", "else", "end", "esac", "except", "export", "false", "False", "fi", "finally", "for", "from",
        "function", "global", "if", "import", "in", "is", "lambda", "local", "module", "next", "nil", "None",
        "nonlocal", "not", "null", "or", "pass", "raise", "require", "rescue", "return", "self", "then", "true",
        "True", "try", "unless", "until", "while", "with", "yield", "yes", "no", "on", "off", "echo", "begin",
        "ensure", "elsif", "when", "attr_reader", "attr_accessor", "private", "protected", "public", "super",
    ]

    static let sqlKeywords: Set<String> = [
        "select", "from", "where", "and", "or", "not", "insert", "into", "values", "update", "set", "delete",
        "create", "table", "drop", "alter", "index", "join", "left", "right", "inner", "outer", "on", "as", "group",
        "by", "order", "having", "limit", "offset", "null", "is", "in", "exists", "distinct", "union", "all",
        "primary", "key", "foreign", "references", "default", "case", "when", "then", "else", "end", "true",
        "false", "local", "function", "return", "if", "for", "while", "do", "repeat", "until", "nil", "begin",
        "SELECT", "FROM", "WHERE", "AND", "OR", "NOT", "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE",
        "CREATE", "TABLE", "DROP", "ALTER", "INDEX", "JOIN", "LEFT", "RIGHT", "INNER", "OUTER", "ON", "AS",
        "GROUP", "BY", "ORDER", "HAVING", "LIMIT", "OFFSET", "NULL", "IS", "IN", "EXISTS", "DISTINCT", "UNION",
        "ALL", "PRIMARY", "KEY", "FOREIGN", "REFERENCES", "DEFAULT", "CASE", "WHEN", "THEN", "ELSE", "END",
    ]

    public static let cLike = Language(line: ["//"], block: [("/*", "*/")], keywords: cKeywords, backtickStrings: true)
    public static let hash = Language(line: ["#"], block: [], keywords: hashKeywords, backtickStrings: true)
    public static let dashDash = Language(line: ["--"], block: [("/*", "*/")], keywords: sqlKeywords)
    public static let markup = Language(line: [], block: [("<!--", "-->")], keywords: [])
    public static let css = Language(line: [], block: [("/*", "*/")], keywords: ["important", "media", "import", "from", "to"])
    public static let json = Language(line: ["//"], block: [("/*", "*/")], keywords: ["true", "false", "null"],
                                      singleQuoteStrings: false)

    /// The language family for a file, or nil for plain text (no highlighting).
    public static func language(for path: String) -> Language? {
        let name = (path as NSString).lastPathComponent
        let ext = (name as NSString).pathExtension.lowercased()
        if ["Makefile", "Dockerfile", "Gemfile", "Rakefile", "Podfile", "Brewfile", ".zshrc", ".bashrc",
            ".gitignore", ".env", ".profile"].contains(name) { return hash }
        switch ext {
        case "swift", "js", "jsx", "ts", "tsx", "mjs", "cjs", "go", "rs", "java", "kt", "kts", "c", "h", "cc",
             "cpp", "hpp", "m", "mm", "cs", "scala", "dart", "php", "groovy", "gradle", "zig", "vue", "svelte":
            var l = cLike
            // Rust lifetimes and Swift/Kotlin characters are rare; only C-family chars use '…' widely
            if ["rs", "swift", "kt", "kts", "scala"].contains(ext) { l.singleQuoteStrings = false }
            return l
        case "py", "rb", "sh", "bash", "zsh", "fish", "yaml", "yml", "toml", "ini", "conf", "cfg", "r", "pl",
             "properties", "mk", "cmake", "tf", "nix", "ex", "exs", "env":
            return hash
        case "sql", "lua", "hs", "elm": return dashDash
        case "html", "htm", "xml", "plist", "svg", "xib", "storyboard": return markup
        case "css", "scss", "less", "sass": return css
        case "json", "jsonc", "jsonl", "json5": return json
        default: return nil
        }
    }

    public static func tokens(_ text: String, language: Language) -> [Token] {
        let u = Array(text.utf16)
        guard u.count <= maxLength else { return [] }
        var out: [Token] = []
        let n = u.count
        var i = 0
        let lines = language.line.map { Array($0.utf16) }
        let blocks = language.block.map { (Array($0.open.utf16), Array($0.close.utf16)) }

        func starts(_ p: [UInt16], at k: Int) -> Bool {
            guard k + p.count <= n else { return false }
            for j in 0..<p.count where u[k + j] != p[j] { return false }
            return true
        }
        func isIdentStart(_ c: UInt16) -> Bool { (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c == 36 || c >= 0x80 }
        func isDigit(_ c: UInt16) -> Bool { c >= 48 && c <= 57 }
        func isIdent(_ c: UInt16) -> Bool { isIdentStart(c) || isDigit(c) }

        scan: while i < n {
            let c = u[i]
            // comments
            for l in lines where starts(l, at: i) {
                // `#` in the middle of a word (`a#b`, URLs' fragments) is no comment for hash languages
                if l == [35], i > 0, isIdent(u[i - 1]) { break }
                var j = i
                while j < n, u[j] != 10 { j += 1 }
                out.append(Token(kind: .comment, location: i, length: j - i))
                i = j
                continue scan
            }
            for (open, close) in blocks where starts(open, at: i) {
                var j = i + open.count
                while j < n, !starts(close, at: j) { j += 1 }
                j = min(n, j + close.count)
                out.append(Token(kind: .comment, location: i, length: j - i))
                i = j
                continue scan
            }
            // strings
            if c == 34 || (c == 39 && language.singleQuoteStrings) || (c == 96 && language.backtickStrings) {
                // `"""` blocks (Swift, Python, Kotlin)
                let triple = i + 2 < n && u[i + 1] == c && u[i + 2] == c
                var j = i + (triple ? 3 : 1)
                while j < n {
                    if u[j] == 92 { j += 2; continue }   // backslash escape
                    if triple {
                        if j + 2 < n, u[j] == c, u[j + 1] == c, u[j + 2] == c { j += 3; break }
                    } else if u[j] == c {
                        j += 1; break
                    } else if u[j] == 10 && c != 96 {
                        break   // unterminated: stop at the end of the line
                    }
                    j += 1
                }
                j = min(j, n)
                out.append(Token(kind: .string, location: i, length: j - i))
                i = j
                continue
            }
            // numbers (not inside identifiers: `x1`)
            if isDigit(c), i == 0 || !isIdent(u[i - 1]) {
                var j = i + 1
                while j < n, isIdent(u[j]) || (u[j] == 46 && j + 1 < n && isDigit(u[j + 1])) { j += 1 }
                out.append(Token(kind: .number, location: i, length: j - i))
                i = j
                continue
            }
            // words: keyword, function call, type
            if isIdentStart(c) {
                var j = i + 1
                while j < n, isIdent(u[j]) { j += 1 }
                let word = String(utf16CodeUnits: Array(u[i..<j]), count: j - i)
                // `@decorator` / `#selector` / `@objc` count with the word
                let attr = i > 0 && (u[i - 1] == 64)
                var k = j
                while k < n, u[k] == 32 { k += 1 }
                if language.keywords.contains(word) {
                    out.append(Token(kind: .keyword, location: i, length: j - i))
                } else if attr {
                    out.append(Token(kind: .keyword, location: i - 1, length: j - i + 1))
                } else if k < n, u[k] == 40 {
                    out.append(Token(kind: .function, location: i, length: j - i))
                } else if c >= 65 && c <= 90, j - i > 1 {
                    out.append(Token(kind: .type, location: i, length: j - i))
                }
                i = j
                continue
            }
            i += 1
        }
        return out
    }
}
