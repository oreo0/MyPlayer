import Foundation
import CryptoKit

enum CloudArchiveError: LocalizedError {
    case downloading, invalid, changing
    var errorDescription: String? {
        switch self {
        case .downloading: "iCloud 正在下载恢复文件，请稍后重试。"
        case .invalid: "云端快照无效或不完整，已有本地数据保留。"
        case .changing: "数据正在更新，稍后会自动重试备份。"
        }
    }
}

/// Immutable manifests plus content-addressed files keep older snapshots recoverable.
/// This actor never reads or modifies production's data directory.
actor CloudArchive {
    struct Snapshot: Codable {
        var schema = 1
        var id: String
        var created: Date
        var sourceRoot: String
        var files: [String: String]
    }
    struct CacheEntry { var revision: String; var digest: String }
    private var cache: [String: CacheEntry] = [:]
    private var lastFiles: [String: String]?
    private let fm = FileManager.default

    private func coordinated<T>(_ url: URL, writing: Bool, _ action: (URL) throws -> T) throws -> T {
        var coordinationError: NSError?
        var result: Result<T, Error>?
        let coordinator = NSFileCoordinator()
        if writing {
            coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { actual in result = Result { try action(actual) } }
        } else {
            coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { actual in result = Result { try action(actual) } }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CloudArchiveError.invalid }
        return try result.get()
    }
    private func download(_ url: URL) throws {
        if url.lastPathComponent.hasSuffix(".icloud") {
            let name = String(url.lastPathComponent.dropFirst().dropLast(7))
            try? fm.startDownloadingUbiquitousItem(at: url.deletingLastPathComponent().appendingPathComponent(name))
            throw CloudArchiveError.downloading
        }
        let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        if values?.isUbiquitousItem == true && values?.ubiquitousItemDownloadingStatus == .notDownloaded {
            try fm.startDownloadingUbiquitousItem(at: url)
            throw CloudArchiveError.downloading
        }
    }
    private func safe(_ relative: String) -> Bool {
        !relative.isEmpty && !relative.hasPrefix("/") && !relative.split(separator: "/").contains(where: { $0 == ".." || $0 == "." })
    }
    private func validDigest(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { "0123456789abcdef".contains($0) }
    }
    private func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    func backup(local: URL, cloud: URL) throws -> URL? {
        let blobs = cloud.appendingPathComponent("Objects", isDirectory: true)
        let snapshots = cloud.appendingPathComponent("Snapshots", isDirectory: true)
        try fm.createDirectory(at: blobs, withIntermediateDirectories: true)
        try fm.createDirectory(at: snapshots, withIntermediateDirectories: true)
        var files: [String: String] = [:]
        var observedRevisions: [URL: String] = [:]
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey]
        guard let enumerator = fm.enumerator(at: local, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { throw CloudArchiveError.invalid }
        for case let file as URL in enumerator {
            let values = try file.resourceValues(forKeys: Set(keys))
            guard values.isSymbolicLink != true else { throw CloudArchiveError.invalid }
            guard values.isRegularFile == true else { continue }
            let basePath = local.standardizedFileURL.resolvingSymlinksInPath().path
            let filePath = file.standardizedFileURL.path
            guard filePath.hasPrefix(basePath + "/") else { throw CloudArchiveError.invalid }
            let relative = String(filePath.dropFirst(basePath.count + 1))
            guard safe(relative) else { throw CloudArchiveError.invalid }
            let revision = UserDataFiles.revision(file)
            let hash: String
            if let cached = cache[relative], cached.revision == revision,
               fm.fileExists(atPath: blobs.appendingPathComponent(cached.digest).path) {
                hash = cached.digest
            } else {
                let data = try Data(contentsOf: file, options: .mappedIfSafe)
                hash = digest(data)
                let target = blobs.appendingPathComponent(hash)
                if !fm.fileExists(atPath: target.path) {
                    try coordinated(target, writing: true) { try data.write(to: $0, options: .atomic) }
                }
                guard UserDataFiles.revision(file) == revision else { throw CloudArchiveError.changing }
                cache[relative] = CacheEntry(revision: revision, digest: hash)
            }
            files[relative] = hash
            observedRevisions[file] = revision
        }
        guard observedRevisions.allSatisfy({ UserDataFiles.revision($0.key) == $0.value }) else { throw CloudArchiveError.changing }
        guard !files.isEmpty else { return nil }
        guard lastFiles != files else { return nil }
        // Publish only after every referenced object has been written.
        let id = String(format: "%.0f", Date().timeIntervalSince1970 * 1000) + "-" + UUID().uuidString
        let snapshot = Snapshot(id: id, created: Date(), sourceRoot: local.path, files: files)
        let destination = snapshots.appendingPathComponent(id + ".json")
        let data = try JSONEncoder().encode(snapshot)
        try coordinated(destination, writing: true) { try data.write(to: $0, options: .atomic) }
        lastFiles = files
        return destination
    }

    /// A manifest arriving first is not evidence that all of its objects uploaded.
    func uploadProgress(snapshot: URL, cloud: URL) throws -> (uploaded: Int, total: Int) {
        let data = try coordinated(snapshot, writing: false) { try Data(contentsOf: $0) }
        let saved = try JSONDecoder().decode(Snapshot.self, from: data)
        guard saved.schema == 1, saved.files.values.allSatisfy(validDigest) else { throw CloudArchiveError.invalid }
        let urls = [snapshot] + Set(saved.files.values).map { cloud.appendingPathComponent("Objects").appendingPathComponent($0) }
        var uploaded = 0
        for url in urls {
            let values = try url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemIsUploadedKey, .ubiquitousItemUploadingErrorKey])
            if let error = values.ubiquitousItemUploadingError { throw error }
            if values.isUbiquitousItem == true && values.ubiquitousItemIsUploaded == true { uploaded += 1 }
        }
        return (uploaded, urls.count)
    }

    /// Reinstallation restores only when the local library is missing. Existing
    /// local edits are never replaced by a different Mac's last-writer snapshot.
    func restoreIfNeeded(local: URL, cloud: URL) throws -> Bool {
        guard !["library.json", "preferences.plist", "app-defaults.plist"].contains(where: {
            fm.fileExists(atPath: local.appendingPathComponent($0).path)
        }) else { return false }
        let folder = cloud.appendingPathComponent("Snapshots", isDirectory: true)
        guard fm.fileExists(atPath: folder.path) else { return false }
        let entries = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        // Do not mistake an undownloaded cloud snapshot for an empty archive.
        for entry in entries where entry.lastPathComponent.hasSuffix(".icloud") { try download(entry) }
        guard let latest = entries.filter({ $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent > $1.lastPathComponent }).first else { return false }
        try download(latest)
        let data = try coordinated(latest, writing: false) { try Data(contentsOf: $0) }
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
        guard snapshot.schema == 1, !snapshot.files.isEmpty, snapshot.files.count < 1_000_000 else { throw CloudArchiveError.invalid }
        let parent = local.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let stage = parent.appendingPathComponent(".MyPlayer-cloud-restore-" + UUID().uuidString)
        try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: stage) }
        for (relative, hash) in snapshot.files {
            guard safe(relative), validDigest(hash) else { throw CloudArchiveError.invalid }
            let blob = cloud.appendingPathComponent("Objects").appendingPathComponent(hash)
            try download(blob)
            let bytes = try coordinated(blob, writing: false) { try Data(contentsOf: $0, options: .mappedIfSafe) }
            guard digest(bytes) == hash else { throw CloudArchiveError.invalid }
            let target = stage.appendingPathComponent(relative)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try bytes.write(to: target, options: .atomic)
        }
        // Resolve managed artwork/lyrics paths after restoring to a new Mac/home.
        func relocate(_ value: Any) -> Any {
            if let string = value as? String, string.hasPrefix(snapshot.sourceRoot + "/") { return local.path + string.dropFirst(snapshot.sourceRoot.count) }
            if let array = value as? [Any] { return array.map(relocate) }
            if let dict = value as? [String: Any] { return dict.mapValues(relocate) }
            return value
        }
        for relative in snapshot.files.keys where ["json", "plist"].contains(URL(fileURLWithPath: relative).pathExtension) {
            let target = stage.appendingPathComponent(relative)
            let bytes = try Data(contentsOf: target)
            if target.pathExtension == "json" {
                let object = try JSONSerialization.jsonObject(with: bytes, options: .fragmentsAllowed)
                try JSONSerialization.data(withJSONObject: relocate(object), options: [.sortedKeys, .fragmentsAllowed]).write(to: target, options: .atomic)
            } else {
                let object = try PropertyListSerialization.propertyList(from: bytes, format: nil)
                try PropertyListSerialization.data(fromPropertyList: relocate(object), format: .xml, options: 0).write(to: target, options: .atomic)
            }
        }
        let backup = parent.appendingPathComponent("MyPlayer Beta Before Cloud Restore-" + UUID().uuidString)
        let existed = fm.fileExists(atPath: local.path)
        if existed { try fm.moveItem(at: local, to: backup) }
        do { try fm.moveItem(at: stage, to: local) }
        catch { if existed { try? fm.moveItem(at: backup, to: local) }; throw error }
        return true
    }
}
