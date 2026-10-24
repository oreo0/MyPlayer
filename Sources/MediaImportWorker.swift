import Foundation

struct MediaImportReport: Sendable {
    var songs: [Song] = []
    var discovered = Set<String>()
    var existing = 0
    var excluded = 0
    var failed = 0
    var unreadable: [String] = []
}

enum MediaImportWorker {
    static func read(urls: [URL], existing: Set<String>, excluded: Set<String>, baselineOnly: Bool) -> MediaImportReport {
        let scopes = urls.filter { $0.startAccessingSecurityScopedResource() }
        defer { scopes.forEach { $0.stopAccessingSecurityScopedResource() } }
        let discovery = FileImporter.discover(urls)
        var report = MediaImportReport()
        report.unreadable = discovery.unreadable
        let extensions = Set(FileImporter.supportedExtensions)
        for url in discovery.files where extensions.contains(url.pathExtension.lowercased()) {
            let path = FolderScanCatalog.key(url)
            report.discovered.insert(path)
            if existing.contains(path) { report.existing += 1; continue }
            if excluded.contains(path) { report.excluded += 1; continue }
            if baselineOnly { continue }
            if let song = autoreleasepool(invoking: { Song.load(at: url) }) { report.songs.append(song) }
            else { report.failed += 1 }
        }
        return report
    }
}
