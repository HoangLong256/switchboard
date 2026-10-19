import Foundation

/// What the file viewer shows for a path.
public enum FileContent: Equatable, Sendable {
    case text(String, truncated: Bool)
    case image
    case binary(size: Int64)
    case unreadable(String)

    public static let textLimit = 2 * 1024 * 1024
    static let imageTypes: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "webp", "tiff", "bmp", "ico", "icns", "pdf"]

    /// A NUL byte in the first 8 KB counts as binary; text is read up to `limit` bytes.
    public static func load(_ path: String, limit: Int = textLimit) -> FileContent {
        let ext = (path as NSString).pathExtension.lowercased()
        if imageTypes.contains(ext) { return .image }
        guard let h = FileHandle(forReadingAtPath: path) else { return .unreadable("Can't open this file.") }
        defer { try? h.close() }
        let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value ?? 0
        guard let data = try? h.read(upToCount: limit) else { return .text("", truncated: false) }
        if data.prefix(8192).contains(0) { return .binary(size: size) }
        return .text(String(decoding: data, as: UTF8.self), truncated: Int64(data.count) < size)
    }

    public static func isMarkdown(_ path: String) -> Bool {
        ["md", "markdown", "mdx"].contains((path as NSString).pathExtension.lowercased())
    }
}
