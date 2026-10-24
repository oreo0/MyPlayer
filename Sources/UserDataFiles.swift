import Foundation

extension Notification.Name {
    static let myPlayerDataChanged = Notification.Name("MyPlayer.userDataChanged")
    static let myPlayerDataConflict = Notification.Name("MyPlayer.userDataConflict")
}

/// Only accepted disk revisions may be overwritten. An external replacement
/// invalidates pending snapshots, even if it arrives while a save is queued.
enum UserDataFiles {
    private static let lock = NSRecursiveLock()
    private static let queue = DispatchQueue(label: "com.myplayer.user-data", qos: .utility)
    private static var revisions: [String: String] = [:]
    private static var epochs: [String: Int] = [:]
    private static var tickets: [String: Int] = [:]
    static func revision(_ url: URL) -> String {
        guard let a = try? FileManager.default.attributesOfItem(atPath: url.path) else { return "missing" }
        return "\(a[.systemFileNumber] ?? 0)-\(a[.size] ?? 0)-\((a[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)"
    }
    @discardableResult static func accept(_ url: URL, expectedRevision: String? = nil) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let current = revision(url)
        if let expectedRevision, current != expectedRevision {
            DispatchQueue.main.async { NotificationCenter.default.post(name: .myPlayerDataConflict, object: url) }
            return false
        }
        revisions[url.path] = current
        epochs[url.path, default: 0] += 1
        return true
    }
    static func isCurrent(_ url: URL) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return (revisions[url.path] ?? "missing") == revision(url)
    }
    static func save<T: Encodable & Sendable>(_ snapshot: T, to url: URL) {
        enqueue(to: url) { try? JSONEncoder().encode(snapshot) }
    }
    static func write(_ data: Data, to url: URL) { enqueue(to: url) { data } }
    private static func enqueue(to url: URL, encode: @escaping @Sendable () -> Data?) {
        lock.lock()
        let epoch = epochs[url.path, default: 0]
        tickets[url.path, default: 0] += 1
        let ticket = tickets[url.path, default: 0]
        lock.unlock()
        queue.async {
            lock.lock()
            let current = ticket == tickets[url.path, default: 0] && epoch == epochs[url.path, default: 0]
            lock.unlock()
            guard current, let data = encode() else { return }
            lock.lock(); defer { lock.unlock() }
            guard ticket == tickets[url.path, default: 0], epoch == epochs[url.path, default: 0] else { return }
            guard (revisions[url.path] ?? "missing") == revision(url) else {
                DispatchQueue.main.async { NotificationCenter.default.post(name: .myPlayerDataConflict, object: url) }
                return
            }
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
                revisions[url.path] = revision(url)
            } catch {
                DispatchQueue.main.async { NotificationCenter.default.post(name: .myPlayerDataConflict, object: url, userInfo: ["error": error.localizedDescription]) }
            }
        }
    }
    static func flush() { queue.sync { } }
}
