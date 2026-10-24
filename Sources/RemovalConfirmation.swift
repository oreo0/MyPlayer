import AppKit

/// Explicit user removals share one gate. Playback consuming the queue is not a
/// removal command and continues through the existing model methods.
@MainActor enum RemovalConfirmation {
    struct Request { let title: String; let message: String }
    // Used only by isolated tests to exercise cancel/confirm without user data.
    private static var isPresenting = false
    static var presenter: ((Request, @escaping (Bool) -> Void) -> Void)?
    static func request(_ title: String, message: String, action: @escaping () -> Void) {
        guard !isPresenting else { return }
        isPresenting = true
        var completed = false
        let completion: (Bool) -> Void = { confirmed in
            guard !completed else { return }; completed = true
            isPresenting = false
            if confirmed { action() }
        }
        if let presenter { presenter(Request(title: title, message: message), completion); return }
        DispatchQueue.main.async {
            guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { completion(false); NSSound.beep(); return }
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = title
            alert.informativeText = message
            let cancel = alert.addButton(withTitle: "取消")
            cancel.keyEquivalent = "\u{1b}"
            let confirm = alert.addButton(withTitle: "确认移除")
            confirm.keyEquivalent = "" // Return must never confirm a removal accidentally.
            alert.beginSheetModal(for: window) { response in completion(response == .alertSecondButtonReturn) }
        }
    }
}

@MainActor extension PlayerManager {
    func confirmRemoveSong(_ song: Song) {
        RemovalConfirmation.request("从资料库移除文件？", message: "将移除《\(song.title)》的资料库记录，磁盘上的原文件会保留。") { self.removeSong(song) }
    }
    func confirmDequeue(_ song: Song) {
        RemovalConfirmation.request("从播放队列移除文件？", message: "将从播放队列移除《\(song.title)》。") { self.dequeue(song) }
    }
    func confirmRemoveFromQueue(_ song: Song) {
        RemovalConfirmation.request("从播放队列移除文件？", message: "将从播放队列移除《\(song.title)》。") { self.removeFromQueue(song) }
    }
    func confirmClearQueue() {
        RemovalConfirmation.request("清空播放队列？", message: "将移除队列中的全部待播文件。") { self.clearQueue() }
    }
    func confirmStopWatchingFolder(_ folder: WatchedMediaFolder) {
        RemovalConfirmation.request("停止扫描此文件夹？", message: "将从自动扫描列表移除“\(folder.path)”。") { self.stopWatchingFolder(folder) }
    }
    func confirmUnmatchLyrics(for song: Song) {
        RemovalConfirmation.request("解除当前匹配？", message: "将解除《\(song.title)》与当前歌词／字幕文件的关联。") { self.unmatchLyrics(for: song) }
    }
    func confirmToggleFavorite(_ song: Song) {
        guard let current = library.first(where: { $0.id == song.id }) else { return }
        guard current.isFavorite else { toggleFavorite(current); return }
        RemovalConfirmation.request("取消喜欢此文件？", message: "将《\(current.title)》从“我喜欢”中移除。") {
            if let latest = self.library.first(where: { $0.id == current.id }), latest.isFavorite { self.toggleFavorite(latest) }
        }
    }
}

@MainActor extension CollectionStore {
    func confirmDelete(_ id: UUID) {
        guard let item = collections.first(where: { $0.id == id }) else { return }
        RemovalConfirmation.request("删除合集？", message: "将删除“\(item.name)”，资料库中的文件会保留。") { self.delete(id) }
    }
    func confirmRemove(_ song: UUID, from id: UUID) {
        guard let item = collections.first(where: { $0.id == id }) else { return }
        RemovalConfirmation.request("从合集移除文件？", message: "将从“\(item.name)”移除该文件。") { self.remove(song, from: id) }
    }
}
