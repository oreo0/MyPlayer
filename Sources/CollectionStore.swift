import Foundation
import Combine

struct MusicCollection: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var songIDs: [UUID] = []
    mutating func append(_ ids: [UUID]) {
        var existing = Set(songIDs)
        songIDs.append(contentsOf: ids.filter { existing.insert($0).inserted })
    }
}

@MainActor final class CollectionStore: ObservableObject {
    @Published private(set) var collections: [MusicCollection] = []
    private let url: URL
    private let writer = LibraryPersistence()
    private var observer: NSObjectProtocol?
    init(url: URL? = nil) {
        self.url = url ?? UserDataStore.shared.file("collections.json")
        try? FileManager.default.createDirectory(at: self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        reload()
        observer = NotificationCenter.default.addObserver(forName: .myPlayerDataChanged, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated { if (note.object as? Set<String>)?.contains("collections.json") == true { self?.reload() } }
        }
    }
    private func reload() {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let revision = UserDataFiles.revision(url)
            let data = try Data(contentsOf: url)
            let saved = try JSONDecoder().decode([MusicCollection].self, from: data)
            guard Set(saved.map(\.id)).count == saved.count else { throw CocoaError(.fileReadCorruptFile) }
            guard UserDataFiles.accept(url, expectedRevision: revision) else { return }
            collections = saved
        } catch { UserDataStore.shared.report("collections.json 无法读取，当前合集已保留，文件不会被覆盖。") }
    }
    @discardableResult func create(_ name: String, songs: [UUID] = []) -> UUID {
        var collection = MusicCollection(name: normalized(name))
        collection.append(songs)
        collections.append(collection); save()
        return collection.id
    }
    func rename(_ id: UUID, to name: String) {
        guard let i = collections.firstIndex(where: { $0.id == id }) else { return }
        collections[i].name = normalized(name); save()
    }
    func delete(_ id: UUID) { collections.removeAll { $0.id == id }; save() }
    func add(_ ids: [UUID], to id: UUID) {
        guard let i = collections.firstIndex(where: { $0.id == id }) else { return }
        collections[i].append(ids); save()
    }
    func remove(_ song: UUID, from id: UUID) {
        guard let i = collections.firstIndex(where: { $0.id == id }) else { return }
        collections[i].songIDs.removeAll { $0 == song }; save()
    }
    func flush() { writer.flush() }
    private func normalized(_ name: String) -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "未命名合集" : name
    }
    private func save() { writer.save(collections, to: url) }
}

