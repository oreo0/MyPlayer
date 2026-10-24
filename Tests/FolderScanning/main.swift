import Foundation

@main struct FolderScanningChecks {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let nested = root.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func writeWave(_ url: URL) throws {
            var data = Data()
            func text(_ value: String) { data.append(contentsOf: value.utf8) }
            func u16(_ value: UInt16) { var x = value.littleEndian; withUnsafeBytes(of: &x) { data.append(contentsOf: $0) } }
            func u32(_ value: UInt32) { var x = value.littleEndian; withUnsafeBytes(of: &x) { data.append(contentsOf: $0) } }
            let bytes: UInt32 = 22050 * 2
            text("RIFF"); u32(bytes + 36); text("WAVEfmt "); u32(16); u16(1); u16(1)
            u32(22050); u32(44100); u16(2); u16(16); text("data"); u32(bytes)
            data.append(Data(repeating: 0, count: Int(bytes)))
            try data.write(to: url)
        }
        let existingURL = root.appendingPathComponent("existing.wav")
        let removedURL = nested.appendingPathComponent("removed.WAV")
        let newURL = nested.appendingPathComponent("new.wav")
        for url in [existingURL, removedURL, newURL] { try writeWave(url) }
        try Data("invalid media".utf8).write(to: nested.appendingPathComponent("broken.mp3"))
        try Data("[00:00]Lyrics".utf8).write(to: nested.appendingPathComponent("new.lrc"))
        var catalog = FolderScanCatalog()
        catalog.watch(root); catalog.watch(root.appendingPathComponent("."))
        precondition(catalog.folders.count == 1)
        catalog.exclude(removedURL)
        let existing = Set([FolderScanCatalog.key(existingURL)])
        let snapshot = catalog
        let report = await Task.detached {
            MediaImportWorker.read(urls: [root, newURL], existing: existing, excluded: snapshot.excludedPaths, baselineOnly: false)
        }.value
        precondition(report.songs.count == 1 && FolderScanCatalog.key(report.songs[0].url) == FolderScanCatalog.key(newURL))
        precondition(report.existing == 1 && report.excluded == 1 && report.failed == 1)
        precondition(report.discovered.count == 4) // No lyrics prerequisite and no duplicate path.
        let saved = try JSONDecoder().decode(FolderScanCatalog.self, from: JSONEncoder().encode(catalog))
        precondition(!saved.permits(removedURL, existing: existing))
        var restored = saved
        restored.allowExplicitFile(removedURL)
        precondition(restored.permits(removedURL, existing: existing))
        var migrated = FolderScanCatalog()
        migrated.establishBaseline(discovered: report.discovered, existing: existing)
        precondition(!migrated.permits(removedURL, existing: existing))
        let futureURL = root.appendingPathComponent("later.wav")
        precondition(migrated.permits(futureURL, existing: existing))
        let offline = MediaImportWorker.read(urls: [root.appendingPathComponent("offline")], existing: [], excluded: [], baselineOnly: false)
        precondition(offline.unreadable.count == 1 && offline.songs.isEmpty)
        print("PASS: real WAV import without LRC, recursive deduplication, corrupt-file reporting, saved exclusions, explicit restore, legacy baseline, future discovery and offline-folder handling")
    }
}
