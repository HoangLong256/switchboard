import Foundation

/// A text file opened for editing, with VS Code's rules for changes on disk
/// (`textFileEditorModelManager`, `textFileSaveErrorHandler`):
/// - a clean document follows the file on disk (silent reload)
/// - a dirty one is never reloaded behind your back
/// - saving over a file that changed since it was loaded is a *conflict*: compare or overwrite
public struct TextDocument: Equatable, Sendable {
    public enum Load: Equatable, Sendable {
        case text
        /// NUL in the first 512 bytes, or not valid UTF-8
        case binary
        /// larger than the limit; can still be opened on request
        case tooLarge(Int64)
        case missing
        case unreadable(String)
    }

    public enum SaveResult: Equatable, Sendable {
        case saved
        /// the file on disk is newer than what was loaded; nothing was written
        case conflict
        case failed(String)
    }

    /// VS Code checks the first 512 bytes for NUL (`encoding.ts`)
    public static let sniffBytes = 512
    public static let largeLimit: Int64 = 20 * 1024 * 1024

    public let path: String
    public private(set) var load: Load = .missing
    /// what the editor shows and edits
    public var text = ""
    /// what was last loaded from or written to disk
    public private(set) var savedText = ""
    /// modification date and size at the last load or save, to notice changes made by someone else
    public private(set) var diskStamp: Stamp?

    public struct Stamp: Equatable, Sendable {
        public let modified: Date
        public let size: Int64
    }

    public var isDirty: Bool { load == .text && text != savedText }

    public init(path: String) { self.path = path }

    /// Reads the file. `force` opens binary-looking or large files anyway (as text, lossy).
    public static func open(_ path: String, force: Bool = false) -> TextDocument {
        var d = TextDocument(path: path)
        d.read(force: force)
        return d
    }

    public static func stamp(_ path: String) -> Stamp? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: path),
              let m = a[.modificationDate] as? Date else { return nil }
        return Stamp(modified: m, size: (a[.size] as? NSNumber)?.int64Value ?? 0)
    }

    private mutating func read(force: Bool) {
        guard let stamp = Self.stamp(path) else { load = .missing; return }
        if !force && stamp.size > Self.largeLimit { load = .tooLarge(stamp.size); diskStamp = stamp; return }
        guard let data = FileManager.default.contents(atPath: path) else { load = .unreadable("Can't read this file."); return }
        let decoded = String(data: data, encoding: .utf8)
        if !force && (data.prefix(Self.sniffBytes).contains(0) || decoded == nil) {
            load = .binary
            diskStamp = stamp
            return
        }
        load = .text
        text = decoded ?? String(decoding: data, as: UTF8.self)
        savedText = text
        diskStamp = stamp
    }

    /// The file on disk differs from what was loaded or saved last.
    public var changedOnDisk: Bool { Self.stamp(path) != diskStamp }

    /// Follows the file on disk if this document is clean and the file changed. Returns whether it reloaded.
    @discardableResult
    public mutating func reloadIfClean() -> Bool {
        guard !isDirty, changedOnDisk else { return false }
        let force = load == .text
        read(force: force)
        return true
    }

    /// Throws away the edits and reads the file again.
    public mutating func revert() { read(force: load == .text) }

    /// Writes `text` unless the file changed on disk since it was loaded (then `.conflict`, nothing written),
    /// or always with `overwrite`.
    public mutating func save(overwrite: Bool = false) -> SaveResult {
        guard load == .text else { return .failed("Not a text document.") }
        if !overwrite, Self.stamp(path) != nil, changedOnDisk { return .conflict }
        do {
            try Data(text.utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
            savedText = text
            diskStamp = Self.stamp(path)
            return .saved
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Current contents on disk, for "Compare".
    public func diskText() -> String {
        FileManager.default.contents(atPath: path).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }
}
