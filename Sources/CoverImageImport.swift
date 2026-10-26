import Foundation

/// Decode/convert selected originals off the main actor, keeping playback responsive.
enum CoverImageImport {
    static func file(_ url: URL) async throws -> Data? {
        try await Task.detached(priority: .userInitiated) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            return try SourceMediaEditor.normalizedArtwork(Data(contentsOf: url))
        }.value
    }
    static func photo(_ data: Data) async throws -> Data? {
        try await Task.detached(priority: .userInitiated) { try SourceMediaEditor.normalizedArtwork(data) }.value
    }
}
