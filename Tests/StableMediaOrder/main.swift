import Foundation
struct Item { let id: String; let title: String; let artist: String }
let original = (0..<100).reversed().map { Item(id: String(format: "%03d", $0), title: "track\($0 % 4)", artist: "artist\($0 % 3)") }
var values = original
for _ in 0..<20 {
    for comparator in [KeyPathComparator(\Item.title), KeyPathComparator(\Item.title, order: .reverse), KeyPathComparator(\Item.artist)] {
        values = StableMediaOrder.sorted(values, using: [comparator], identity: { $0.id })
        precondition(Set(values.map(\.id)).count == 100)
        let again = StableMediaOrder.sorted(Array(values.reversed()), using: [comparator], identity: { $0.id })
        precondition(again.map(\.id) == values.map(\.id))
        for pair in zip(values, values.dropFirst()) {
            let order = comparator.compare(pair.0, pair.1)
            precondition(order != .orderedDescending)
            if order == .orderedSame { precondition(pair.0.id < pair.1.id) }
        }
    }
}
print("PASS: repeated column sorts, descending order, equal-key identity and unique rows")
