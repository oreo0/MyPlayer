import Foundation

struct WatchedMediaFolder: Identifiable, Codable, Sendable {
    var path: String
    var bookmark: Data?
    var id: String { path }
    var url: URL {
        guard let bookmark else { return URL(fileURLWithPath: path) }
        var stale = false
        return (try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale)) ?? URL(fileURLWithPath: path)
    }
}

struct FolderScanCatalog: Codable, Sendable {
    var folders: [WatchedMediaFolder] = []
    var excludedPaths = Set<String>()
    var hasBaseline = false
    static func key(_ url: URL) -> String { url.standardizedFileURL.resolvingSymlinksInPath().path }
    mutating func watch(_ url: URL) {
        let path = Self.key(url)
        let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        if let index = folders.firstIndex(where: { $0.path == path }) {
            if let bookmark { folders[index].bookmark = bookmark }
        } else { folders.append(WatchedMediaFolder(path: path, bookmark: bookmark)) }
    }
    mutating func exclude(_ url: URL) { excludedPaths.insert(Self.key(url)) }
    mutating func allowExplicitFile(_ url: URL) { excludedPaths.remove(Self.key(url)) }
    mutating func establishBaseline(discovered: Set<String>, existing: Set<String>) {
        excludedPaths.formUnion(discovered.subtracting(existing))
        hasBaseline = true
    }
    func permits(_ url: URL, existing: Set<String>) -> Bool {
        let path = Self.key(url)
        return !existing.contains(path) && !excludedPaths.contains(path)
    }
}
