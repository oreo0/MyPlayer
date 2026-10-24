import SwiftUI
import AppKit
import Darwin

@MainActor final class CloudDataController: ObservableObject {
    static let shared = CloudDataController()
    @Published private(set) var status = "正在检查 iCloud Drive…"
    private let archive = CloudArchive()
    private let local = UserDataStore.shared.root
    private var cloud: URL?
    private var watchers: [DispatchSourceFileSystemObject] = []
    private var pending: Task<Void, Never>?
    private var uploadCheck: Task<Void, Never>?
    private var syncing = false
    private var lastSnapshot: URL?
    private var started = false
    private init() {
        let drive = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        if FileManager.default.fileExists(atPath: drive.path) {
            cloud = drive.appendingPathComponent("MyPlayer/Beta/Backup", isDirectory: true)
        }
    }
    func restoreBeforeLoading() async throws -> Bool {
        guard let cloud else { status = "iCloud Drive 不可用；数据保存在本机"; return false }
        status = "正在检查云端恢复快照…"
        let restored = try await archive.restoreIfNeeded(local: local, cloud: cloud)
        if restored { status = "已从 iCloud Drive 恢复用户数据" }
        return restored
    }
    func start() {
        guard !started else { return }; started = true
        guard cloud != nil else { return }
        armWatchers()
        schedule()
    }
    private func schedule() {
        pending?.cancel()
        pending = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            await self?.syncNow()
        }
    }
    func syncNow() async {
        guard let cloud else { status = "iCloud Drive 不可用；请先在系统设置中启用"; return }
        guard !syncing else { schedule(); return }
        syncing = true
        uploadCheck?.cancel()
        defer { syncing = false; armWatchers() }
        UserDataStore.shared.flush()
        status = "正在备份到 iCloud Drive…"
        do {
            if let snapshot = try await archive.backup(local: local, cloud: cloud) { lastSnapshot = snapshot }
            if let lastSnapshot {
                let progress = try await archive.uploadProgress(snapshot: lastSnapshot, cloud: cloud)
                status = progress.uploaded == progress.total ? "iCloud Drive 已上传完整快照" : "iCloud Drive 上传中：\(progress.uploaded)/\(progress.total) 个文件"
                if progress.uploaded != progress.total { monitorUpload(lastSnapshot) }
            } else { status = "本地数据已保留；尚无可备份的资料库" }
        } catch {
            status = "云端备份待重试：\(error.localizedDescription)"
            schedule()
        }
    }
    private func monitorUpload(_ snapshot: URL) {
        uploadCheck?.cancel()
        uploadCheck = Task { [weak self] in
            for _ in 0..<8 {
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
                guard let self else { return }
                if let cloud = self.cloud, let progress = try? await self.archive.uploadProgress(snapshot: snapshot, cloud: cloud) {
                    self.status = progress.uploaded == progress.total ? "iCloud Drive 已上传完整快照" : "iCloud Drive 上传中：\(progress.uploaded)/\(progress.total) 个文件"
                    if progress.uploaded == progress.total { return }
                }
            }
        }
    }
    func openFolder() {
        guard let cloud else { return }
        do { try FileManager.default.createDirectory(at: cloud, withIntermediateDirectories: true); NSWorkspace.shared.open(cloud) }
        catch { status = error.localizedDescription }
    }
    private func armWatchers() {
        watchers.forEach { $0.cancel() }; watchers.removeAll()
        var directories = [local]
        if let enumerator = FileManager.default.enumerator(at: local, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) {
            for case let url as URL in enumerator {
                if let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]), values.isDirectory == true, values.isSymbolicLink != true { directories.append(url) }
            }
        }
        for directory in directories {
            let fd = open(directory.path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
            source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.schedule() } }
            source.setCancelHandler { close(fd) }
            source.resume(); watchers.append(source)
        }
    }
}

@MainActor final class MyPlayerSession: ObservableObject {
    @Published private(set) var player: PlayerManager?
    @Published private(set) var collections: CollectionStore?
    @Published private(set) var error: String?
    private var loading = false
    func load() async {
        guard player == nil, !loading else { return }; loading = true
        defer { loading = false }
        error = nil
        do {
            let restored = try await CloudDataController.shared.restoreBeforeLoading()
            UserDataStore.shared.prepare(restoreFromProduction: !restored)
            collections = CollectionStore()
            player = PlayerManager()
            CloudDataController.shared.start()
        } catch { self.error = error.localizedDescription }
    }
}
