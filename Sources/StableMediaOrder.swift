import Foundation

/// Stable identity breaks equal-column ties, independent of the previous order.
enum StableMediaOrder {
    static func sorted<T>(_ values: [T], using comparators: [KeyPathComparator<T>], identity: (T) -> String) -> [T] {
        values.sorted { a, b in
            for comparator in comparators {
                let order = comparator.compare(a, b)
                if order != .orderedSame { return order == .orderedAscending }
            }
            return identity(a) < identity(b)
        }
    }
}
