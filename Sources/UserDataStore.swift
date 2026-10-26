import Foundation
import AppKit
import Combine
import Darwin

/// The directory is independent of the app bundle, build number and signing.
/// Preferences are mirrored to UserDefaults for @AppStorage, but the portable
/// plist in this directory is the durable, externally editable source.
@MainActor
final class UserDataStore: ObservableObject {
    static let shared = UserDataStore()
    let root: URL
    private let bootstrapsProduction: Bool
    @Published var issue: String?
    let defaults: UserDefaults
    private var extraPreferences: [String: Any] = [:]
    private var currentLyrics: URL?
    private var prepared = false
    private var watchers: [DispatchSourceFileSystemObject] = []
    private var defaultsObserver: NSObjectProtocol?
    private var conflictObserver: NSObjectProtocol?
    private var preferenceWork: DispatchWorkItem?
    private var reloadWork: DispatchWorkItem?
    private var lastPreferences: NSDictionary = [:]
    private var lastAppDefaults: NSDictionary = [:]
    private var examined: [String: String] = [:]
    private var applying = false
    private let names = ["library.json", "collections.json", "folder-scan.json", "preferences.plist", "shortcuts.json", "queue.json", "playback-session.json", "last-playing-song.json"]
    static let preferenceKeys = Set([
        "collectionSidebarPreferredWidth", "betaVisualStyle", "appearanceMode", "closeWindowBehavior", "desktopBackdropStyle", "sidePanelPreferredWidth", "libraryViewStyle", "coverGrouping", "coverSortAscending",
        "lyricsArtworkBackground", "lyricsBlurEnabled", "lyricsCentered", "lyricsFontName", "lyricsFontSize", "sidebarLyricsFontSize", "windowLyricsFontSize", "fullscreenLyricsFontSize", "lyricsFontWeight",
        "nowPlayingShowsLyrics", "nowPlayingSplitView", "showLibraryLyrics", "showMenuBarLyrics",
        "videoLyricsEnabled", "videoLyricsFont", "videoLyricsSize", "videoLyricsStyle", "videoLyricsWeight",
        "libraryColumnSort", "repeatMode", "sortKey", "sortAscending", "autoScanFolders", "usesCustomLibraryOrder"
    ])
    init(root: URL? = nil, defaults: UserDefaults = .standard) {
        self.bootstrapsProduction = root == nil
        self.defaults = defaults
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MyPlayer Beta", isDirectory: true)
    }
    func file(_ name: String) -> URL { root.appendingPathComponent(name) }
    func prepare(restoreFromProduction: Bool = true) {
        guard !prepared else { return }; prepared = true
        do {
            if bootstrapsProduction && restoreFromProduction {
                try BetaDataBootstrap.copyOnce(from: root.deletingLastPathComponent().appendingPathComponent("MyPlayer", isDirectory: true), to: root)
            }
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: file("Lyrics"), withIntermediateDirectories: true)
            UserDataFiles.accept(file("app-defaults.plist"))
            if bootstrapsProduction, let data = try? Data(contentsOf: file("app-defaults.plist")),
               let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
                for (key, value) in values { defaults.set(value, forKey: key) }
            }
            // The snapshot above is independent; all subsequent writes stay in beta.
            if FileManager.default.fileExists(atPath: file("preferences.plist").path) { reloadPreferences() }
            else { lastPreferences = preferences(); persistPreferences(force: true) }
            if LyricsFontSizes.migrate(defaults) { persistPreferences(force: true) }
        } catch { report("无法创建用户数据文件夹：\(error.localizedDescription)") }
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.schedulePreferences() }
        }
        conflictObserver = NotificationCenter.default.addObserver(forName: .myPlayerDataConflict, object: nil, queue: .main) { [weak self] event in
            MainActor.assumeIsolated {
                if let error = event.userInfo?["error"] as? String { self?.report(error) }
                self?.scheduleReload()
            }
        }
        armWatchers()
    }
    private func migrateLegacy() {
        let old = root.deletingLastPathComponent().appendingPathComponent("LyricPlayer", isDirectory: true)
        guard old != root, let entries = try? FileManager.default.contentsOfDirectory(at: old, includingPropertiesForKeys: nil) else { return }
        // A completed migration must never reimport stale defaults on an update.
        let marker = file("migration-v1.json")
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }
        func copyMissing(_ source: URL, _ destination: URL) throws {
            var directory: ObjCBool = false
            if FileManager.default.fileExists(atPath: source.path, isDirectory: &directory), directory.boolValue {
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                for child in try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) { try copyMissing(child, destination.appendingPathComponent(child.lastPathComponent)) }
            } else if !FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.copyItem(at: source, to: destination) }
        }
        do {
            for entry in entries { try copyMissing(entry, file(entry.lastPathComponent)) }
            try Data("{\"schema\":1,\"source\":\"LyricPlayer\"}".utf8).write(to: marker, options: .atomic)
        } catch { report("旧版数据迁移未完成，原文件已保留：\(error.localizedDescription)") }
    }
    func managedLyricsPath(_ path: String?) -> String? {
        guard let path else { return nil }
        // Repair old absolute paths and data imported from a different Mac.
        for component in ["/LyricPlayer/Lyrics/", "/MyPlayer/Lyrics/"] {
            if let range = path.range(of: component) {
                let relative = String(path[range.upperBound...])
                let candidate = file("Lyrics").appendingPathComponent(relative).standardizedFileURL
                if candidate.path.hasPrefix(file("Lyrics").path + "/"), FileManager.default.fileExists(atPath: candidate.path) { return candidate.path }
            }
        }
        return path
    }
    private func preferences() -> NSDictionary {
        let known = defaults.dictionaryRepresentation().filter { Self.preferenceKeys.contains($0.key) }
        return NSDictionary(dictionary: extraPreferences.merging(known) { _, current in current })
    }
    private func schedulePreferences() {
        guard !applying else { return }
        preferenceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.persistPreferences() } }
        preferenceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
    private func persistPreferences(force: Bool = false) {
        if bootstrapsProduction, let identifier = Bundle.main.bundleIdentifier {
            let all = NSDictionary(dictionary: defaults.persistentDomain(forName: identifier) ?? [:])
            if force || !all.isEqual(lastAppDefaults),
               let data = try? PropertyListSerialization.data(fromPropertyList: all, format: .xml, options: 0) {
                lastAppDefaults = all
                UserDataFiles.write(data, to: file("app-defaults.plist"))
            }
        }
        let values = preferences()
        guard force || !values.isEqual(lastPreferences) else { return }
        guard let data = try? PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0) else { return }
        lastPreferences = values
        UserDataFiles.write(data, to: file("preferences.plist"))
    }
    private func reloadPreferences() {
        let url = file("preferences.plist")
        do {
            let revision = UserDataFiles.revision(url)
            let data = try Data(contentsOf: url)
            guard let values = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { throw CocoaError(.propertyListReadCorrupt) }
            // Reject invalid known values before making any setting changes.
            for (key, value) in values where Self.preferenceKeys.contains(key) {
                let isBool = ["coverSortAscending", "lyricsArtworkBackground", "lyricsBlurEnabled", "lyricsCentered", "nowPlayingShowsLyrics", "nowPlayingSplitView", "showLibraryLyrics", "showMenuBarLyrics", "videoLyricsEnabled", "sortAscending", "autoScanFolders", "usesCustomLibraryOrder"].contains(key)
                if isBool && !(value is NSNumber) { throw CocoaError(.propertyListReadCorrupt) }
                if ["sidePanelPreferredWidth", "collectionSidebarPreferredWidth"].contains(key) {
                    guard let number = value as? NSNumber, number.doubleValue.isFinite, (0...720).contains(number.doubleValue) else { throw CocoaError(.propertyListReadCorrupt) }
                } else if ["lyricsFontSize", "sidebarLyricsFontSize", "windowLyricsFontSize", "fullscreenLyricsFontSize", "videoLyricsSize"].contains(key) {
                    guard let number = value as? NSNumber, number.doubleValue.isFinite, (28...72).contains(number.doubleValue) else { throw CocoaError(.propertyListReadCorrupt) }
                } else if !isBool && !(value is String) { throw CocoaError(.propertyListReadCorrupt) }
            }
            guard UserDataFiles.accept(url, expectedRevision: revision) else { return }
            extraPreferences = values.filter { !Self.preferenceKeys.contains($0.key) }
            applying = true
            for (key, value) in values where Self.preferenceKeys.contains(key) { defaults.set(value, forKey: key) }
            applying = false
            lastPreferences = preferences()
        } catch { report("preferences.plist 无法读取，已有设置保留，原文件不会被覆盖。") }
    }
    func report(_ message: String) { issue = message }
    func reloadNow(force: Bool = true) { if force { examined.removeAll() }; inspectChanges(force: force); armWatchers() }
    func watchLyrics(_ url: URL?) {
        guard currentLyrics != url else { return }
        currentLyrics = url
        if let url { examined["currentLyrics"] = UserDataFiles.revision(url) }
        armWatchers()
    }
    private func scheduleReload() {
        reloadWork?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.reloadNow(force: false) } }
        reloadWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }
    private func inspectChanges(force: Bool) {
        var changed = Set<String>()
        if let currentLyrics {
            let revision = UserDataFiles.revision(currentLyrics)
            if let previous = examined["currentLyrics"], previous != revision { changed.insert("Lyrics") }
            examined["currentLyrics"] = revision
        }
        for name in names {
            let url = file(name)
            let revision = UserDataFiles.revision(url)
            guard revision != "missing", (force || !UserDataFiles.isCurrent(url)), examined[name] != revision else { continue }
            examined[name] = revision
            if name == "preferences.plist" { reloadPreferences() }
            changed.insert(name)
        }
        if !changed.isEmpty { NotificationCenter.default.post(name: .myPlayerDataChanged, object: changed) }
    }
    private func armWatchers() {
        watchers.forEach { $0.cancel() }; watchers.removeAll()
        for url in [root, file("Lyrics")] + names.map({ file($0) }) + [currentLyrics].compactMap({ $0 }) {
            let descriptor = open(url.path, O_EVTONLY)
            guard descriptor >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main)
            source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.scheduleReload() } }
            source.setCancelHandler { close(descriptor) }
            source.resume(); watchers.append(source)
        }
    }
    func flush() {
        guard prepared else { return }
        preferenceWork?.cancel()
        persistPreferences()
        UserDataFiles.flush()
    }
}
