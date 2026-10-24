import Foundation
@main struct PersistenceChecks {
    @MainActor static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("library.json")
        let writer = LibraryPersistence()
        for i in 0..<100 { writer.save(Array(0...i), to: target) }
        writer.flush()
        let result = try JSONDecoder().decode([Int].self, from: Data(contentsOf: target))
        precondition(result == Array(0..<100))
        print("PASS: serial coalesced writes retain newest library snapshot and flush on exit")
    }
}
