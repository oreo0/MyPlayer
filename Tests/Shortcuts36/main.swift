import Foundation

@main struct ShortcutTests {
    @MainActor static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("shortcuts.json")
        let store = ShortcutStore(url: url)
        for action in ShortcutAction.allCases {
            precondition(store.binding(action).shortcut != nil)
            precondition(store.reset(action) == nil, "Invalid default: \(action)")
        }
        let custom = ShortcutBinding(key: "k", command: true, option: true)
        precondition(store.set(custom, for: .favorite) == nil)
        precondition(store.set(custom, for: .next) != nil)
        precondition(store.set(ShortcutBinding(key: "q", command: true), for: .next) != nil)
        precondition(store.set(ShortcutBinding(key: "k"), for: .next) != nil)
        UserDataFiles.flush()
        let restored = ShortcutStore(url: url)
        precondition(restored.binding(.favorite) == custom)
        precondition(restored.set(ShortcutBinding(key: ""), for: .favorite) == nil)
        precondition(restored.binding(.favorite).shortcut == nil)
        restored.resetAll(); UserDataFiles.flush()
        precondition(ShortcutStore(url: url).binding(.favorite) == ShortcutAction.favorite.standard)
        print("PASS: all defaults, collisions, reserved keys, persistence, clearing and reset")
    }
}
