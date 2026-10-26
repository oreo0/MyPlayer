import Foundation

struct LibrarySortRule: Codable, Equatable {
    enum Field: String, Codable, CaseIterable { case title, artist, album, duration, playCount }
    var field: Field
    var ascending: Bool
    init(field: Field, ascending: Bool) { self.field = field; self.ascending = ascending }
    init?(_ comparator: KeyPathComparator<Song>) {
        switch comparator.keyPath {
        case \Song.title: field = .title
        case \Song.artist: field = .artist
        case \Song.album: field = .album
        case \Song.duration: field = .duration
        case \Song.playCount: field = .playCount
        default: return nil
        }
        ascending = comparator.order == .forward
    }
    var comparator: KeyPathComparator<Song> {
        let order: SortOrder = ascending ? .forward : .reverse
        switch field {
        case .title: return KeyPathComparator(\Song.title, order: order)
        case .artist: return KeyPathComparator(\Song.artist, order: order)
        case .album: return KeyPathComparator(\Song.album, order: order)
        case .duration: return KeyPathComparator(\Song.duration, order: order)
        case .playCount: return KeyPathComparator(\Song.playCount, order: order)
        }
    }
    static func load(_ defaults: UserDefaults) -> [Self] {
        guard let text = defaults.string(forKey: "libraryColumnSort"), let data = text.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([Self].self, from: data)) ?? []
    }
    static func infer(_ songs: [Song]) -> [Self] {
        for field in Field.allCases {
            for ascending in [true, false] {
                let rule = Self(field: field, ascending: ascending), comparator = rule.comparator
                let pairs = zip(songs, songs.dropFirst()).map { comparator.compare($0, $1) }
                if pairs.contains(.orderedAscending) && !pairs.contains(.orderedDescending) { return [rule] }
            }
        }
        return [Self(field: .title, ascending: true)]
    }
}
