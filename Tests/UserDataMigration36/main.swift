import Foundation

@main struct MigrationTests {
    @MainActor static func main() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let legacy = parent.appendingPathComponent("LyricPlayer")
        let root = parent.appendingPathComponent("MyPlayer")
        let suite = "MyPlayer.Test." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: parent) }
        try FileManager.default.createDirectory(at: legacy.appendingPathComponent("Lyrics"), withIntermediateDirectories: true)
        try Data("[]".utf8).write(to: legacy.appendingPathComponent("library.json"))
        try Data("[00:01]test".utf8).write(to: legacy.appendingPathComponent("Lyrics/test.lrc"))
        defaults.set("dark", forKey: "appearanceMode")
        let store = UserDataStore(root: root, defaults: defaults)
        store.prepare(); store.flush()
        precondition(FileManager.default.fileExists(atPath: root.appendingPathComponent("library.json").path))
        precondition(FileManager.default.fileExists(atPath: legacy.appendingPathComponent("library.json").path))
        precondition(store.managedLyricsPath(legacy.appendingPathComponent("Lyrics/test.lrc").path) == root.appendingPathComponent("Lyrics/test.lrc").path)
        try Data("[ ]".utf8).write(to: root.appendingPathComponent("library.json"), options: .atomic)
        defaults.set("light", forKey: "appearanceMode")
        let nextLaunch = UserDataStore(root: root, defaults: defaults)
        nextLaunch.prepare()
        precondition(defaults.string(forKey: "appearanceMode") == "dark")
        let retained = try Data(contentsOf: root.appendingPathComponent("library.json"))
        precondition(String(decoding: retained, as: UTF8.self) == "[ ]")
        let preferenceURL = root.appendingPathComponent("preferences.plist")
        let imported: [String: Any] = ["appearanceMode": "light", "themeColorName": "red", "futureSetting": "keep"]
        try PropertyListSerialization.data(fromPropertyList: imported, format: .xml, options: 0).write(to: preferenceURL, options: .atomic)
        nextLaunch.reloadNow()
        precondition(defaults.string(forKey: "appearanceMode") == "light")
        precondition(defaults.string(forKey: "themeColorName") == "red")
        defaults.set(36, forKey: "lyricsFontSize"); nextLaunch.flush()
        let exported = try PropertyListSerialization.propertyList(from: Data(contentsOf: preferenceURL), format: nil) as! [String: Any]
        precondition(exported["futureSetting"] as? String == "keep")
        try Data("broken".utf8).write(to: preferenceURL, options: .atomic)
        nextLaunch.reloadNow()
        precondition(defaults.string(forKey: "appearanceMode") == "light")
        defaults.set("green", forKey: "themeColorName"); nextLaunch.flush()
        let invalid = try Data(contentsOf: preferenceURL)
        precondition(String(decoding: invalid, as: UTF8.self) == "broken")
        print("PASS: migration, retained originals, update preservation, live import and corrupt-file protection")
    }
}
