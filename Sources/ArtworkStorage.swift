import Foundation
import CryptoKit

/// Original bytes are preserved on disk. Views map only the current artwork;
/// library metadata and cache keys do not retain the entire artwork collection.
enum ArtworkStorage {
    struct Result: Sendable { let id: UUID; let revision: UUID; let path: String }
    static func externalize(_ songs: [Song], root: URL) -> [Result] {
        let directory = root.appendingPathComponent("Artwork", isDirectory: true)
        guard (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)) != nil else { return [] }
        return songs.compactMap { song in
            autoreleasepool {
                guard let data = song.embeddedArtwork else { return nil }
                let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                let url = directory.appendingPathComponent(digest + ".image")
                do {
                    if !FileManager.default.fileExists(atPath: url.path) { try data.write(to: url, options: .atomic) }
                    // Never drop an embedded original unless the disk copy is complete.
                    guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size == data.count,
                          let verified = try? Data(contentsOf: url, options: .mappedIfSafe), SHA256.hash(data: verified) == SHA256.hash(data: data) else { return nil }
                    return Result(id: song.id, revision: song.artworkRevision, path: url.path)
                } catch { return nil }
            }
        }
    }
    static func relocated(_ path: String?, root: URL) -> String? {
        guard let path else { return nil }
        let candidate = root.appendingPathComponent("Artwork").appendingPathComponent(URL(fileURLWithPath: path).lastPathComponent)
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate.path : path
    }
}
