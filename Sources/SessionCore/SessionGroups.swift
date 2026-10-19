import Foundation

/// Sections of the sessions column when grouped by project or status.
public enum SessionGroups {
    /// Splits `sortedItems` by `key`, keeping the input order inside a group. Groups come in the order of their
    /// first item, so with `SessionOrder` sorting the group holding the most urgent session comes first.
    public static func split<T>(_ sortedItems: [T], key: (T) -> String) -> [(key: String, items: [T])] {
        var order: [String] = []
        var items: [String: [T]] = [:]
        for item in sortedItems {
            let k = key(item)
            if items[k] == nil { order.append(k) }
            items[k, default: []].append(item)
        }
        return order.map { ($0, items[$0] ?? []) }
    }
}
