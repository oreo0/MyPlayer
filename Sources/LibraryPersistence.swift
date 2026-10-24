import Foundation

@MainActor
final class LibraryPersistence {
    func save<T: Encodable & Sendable>(_ snapshot: T, to url: URL) {
        UserDataFiles.save(snapshot, to: url)
    }
    func flush() { UserDataFiles.flush() }
}
