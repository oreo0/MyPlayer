import Foundation
@main struct CollectionChecks {
    @MainActor static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let file = directory.appendingPathComponent("collections.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CollectionStore(url: file)
        let a = UUID(), b = UUID(), c = UUID()
        let first = store.create("  我的合集  ", songs: [a, b, a])
        precondition(store.collections[0].name == "我的合集")
        precondition(store.collections[0].songIDs == [a, b])
        store.add([b, c, a], to: first)
        precondition(store.collections[0].songIDs == [a, b, c])
        store.rename(first, to: "歌曲与视频")
        store.remove(b, from: first)
        let second = store.create(" ")
        store.flush()
        let restored = CollectionStore(url: file)
        precondition(restored.collections[0].id == first)
        precondition(restored.collections[0].name == "歌曲与视频")
        precondition(restored.collections[0].songIDs == [a, c])
        precondition(restored.collections[1].name == "未命名合集")
        restored.delete(first); restored.flush()
        let final = CollectionStore(url: file)
        precondition(final.collections.map(\.id) == [second])
        print("PASS: create/rename/delete, insertion order, duplicate prevention, removal and persisted reload")
    }
}
