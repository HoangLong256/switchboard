import Foundation

/// Line by line comparison of two versions of a file, laid out like VS Code's diff editor: unchanged lines side
/// by side, removed lines on the left, added on the right, and a changed block paired up row by row.
public enum LineDiff {
    public enum Kind: Equatable, Sendable {
        case same, removed, added
        /// a removed and an added line in the same row
        case changed
    }

    public struct Row: Equatable, Sendable {
        public let kind: Kind
        /// 1-based line numbers; nil on the side that has no line in this row
        public let oldNumber: Int?
        public let newNumber: Int?
        public let oldText: String?
        public let newText: String?
    }

    /// A run of rows to show, or unchanged rows folded away ("⋯ 42 unchanged lines").
    public enum Item: Equatable, Sendable {
        case row(Int)
        case fold(Range<Int>)
    }

    /// Diffs above this many lines in total are not computed (they would take long and help little).
    public static let maxLines = 60_000

    public static func lines(_ text: String) -> [String] {
        var l = text.components(separatedBy: "\n")
        if l.last == "" { l.removeLast() }   // the newline at the end of the file
        return l.map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
    }

    public static func rows(old: [String], new: [String]) -> [Row] {
        let diff = new.difference(from: old)
        var removed = Set<Int>(), inserted = Set<Int>()
        for change in diff {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        var rows: [Row] = []
        var i = 0, j = 0
        while i < old.count || j < new.count {
            let del = i < old.count && removed.contains(i)
            let ins = j < new.count && inserted.contains(j)
            guard del || ins else {
                rows.append(Row(kind: .same, oldNumber: i + 1, newNumber: j + 1, oldText: old[i], newText: new[j]))
                i += 1; j += 1
                continue
            }
            // one block of removals and insertions between two unchanged lines
            var dels: [Int] = [], inss: [Int] = []
            while (i < old.count && removed.contains(i)) || (j < new.count && inserted.contains(j)) {
                if i < old.count && removed.contains(i) { dels.append(i); i += 1 } else { inss.append(j); j += 1 }
            }
            for k in 0..<max(dels.count, inss.count) {
                let o = k < dels.count ? dels[k] : nil, n = k < inss.count ? inss[k] : nil
                let kind: Kind = o != nil && n != nil ? .changed : (o != nil ? .removed : .added)
                rows.append(Row(kind: kind, oldNumber: o.map { $0 + 1 }, newNumber: n.map { $0 + 1 },
                                oldText: o.map { old[$0] }, newText: n.map { new[$0] }))
            }
        }
        return rows
    }

    /// Folds runs of unchanged rows longer than `minimum`, keeping `context` rows next to each change.
    public static func fold(_ rows: [Row], context: Int = 3, minimum: Int = 8) -> [Item] {
        var items: [Item] = []
        var i = 0
        while i < rows.count {
            guard rows[i].kind == .same else { items.append(.row(i)); i += 1; continue }
            var end = i
            while end < rows.count, rows[end].kind == .same { end += 1 }
            // keep context after the previous change and before the next one (none at the file's edges)
            let keepStart = i == 0 ? 0 : context
            let keepEnd = end == rows.count ? 0 : context
            let foldFrom = i + keepStart, foldTo = end - keepEnd
            if foldTo - foldFrom >= minimum {
                items += (i..<foldFrom).map(Item.row)
                items.append(.fold(foldFrom..<foldTo))
                items += (foldTo..<end).map(Item.row)
            } else {
                items += (i..<end).map(Item.row)
            }
            i = end
        }
        return items
    }

    /// "+12 −3"
    public static func stats(_ rows: [Row]) -> (added: Int, removed: Int) {
        rows.reduce((0, 0)) { acc, r in
            switch r.kind {
            case .same: acc
            case .added: (acc.0 + 1, acc.1)
            case .removed: (acc.0, acc.1 + 1)
            case .changed: (acc.0 + 1, acc.1 + 1)
            }
        }
    }
}
