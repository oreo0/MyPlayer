import Foundation
import Combine

/// Keys are generated once per entry, never inside the sort comparator.
enum MediaCoverOrdering {
    static func key(_ title: String) -> String {
        let latin = title.unicodeScalars.allSatisfy(\.isASCII) ? title : (title.applyingTransform(.toLatin, reverse: false) ?? title)
        return latin.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: .whitespacesAndNewlines).joined()
    }
    static func sorted<T>(_ values: [T], ascending: Bool, title: (T) -> String) throws -> [T] {
        var entries: [(value: T, key: String, index: Int)] = []
        for (index, value) in values.enumerated() {
            try Task.checkCancellation()
            entries.append((value, key(title(value)), index))
        }
        let locale = Locale(identifier: "en_US_POSIX")
        entries.sort { lhs, rhs in
            let order = lhs.key.compare(rhs.key, options: [.numeric], locale: locale)
            if order == .orderedSame { return lhs.index < rhs.index }
            return ascending ? order == .orderedAscending : order == .orderedDescending
        }
        try Task.checkCancellation()
        return entries.map(\.value)
    }
    static func build(_ songs: [Song], grouping: CoverGrouping, ascending: Bool) throws -> [MediaCoverGroup] {
        var groups = grouping.groups(songs)
        for index in groups.indices {
            try Task.checkCancellation()
            groups[index].songs = try sorted(groups[index].songs, ascending: ascending, title: \.title)
        }
        return try sorted(groups, ascending: ascending, title: \.title)
    }
}

@MainActor final class CoverCatalog: ObservableObject {
    @Published private(set) var groups: [MediaCoverGroup] = []
    private var songs: [Song] = []
    private var grouping: CoverGrouping?
    private var ascending = true
    private var generation = UUID()
    private var worker: Task<[MediaCoverGroup]?, Never>?
    private var completion: Task<Void, Never>?
    private var pending = false
    private(set) var rebuilds = 0
    func update(_ songs: [Song], grouping: CoverGrouping, ascending: Bool) {
        guard self.grouping != grouping || self.ascending != ascending || self.songs != songs else { return }
        self.songs = songs; self.grouping = grouping; self.ascending = ascending
        worker?.cancel(); completion?.cancel()
        let token = UUID(); generation = token; rebuilds += 1; pending = true
        let work = Task.detached(priority: .utility) {
            try? MediaCoverOrdering.build(songs, grouping: grouping, ascending: ascending)
        }
        worker = work
        completion = Task { [weak self] in
            guard let built = await work.value, !Task.isCancelled, let self, self.generation == token else { return }
            self.pending = false
            self.groups = built
        }
    }
    func suspend() {
        worker?.cancel(); completion?.cancel()
        if pending { grouping = nil }
        pending = false
    }
    deinit { worker?.cancel(); completion?.cancel() }
}
