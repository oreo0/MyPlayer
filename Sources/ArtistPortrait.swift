import SwiftUI
import AppKit
import CryptoKit

@MainActor enum ArtistPortraitStorage {
    static func url(for artist: String, root: URL = UserDataStore.shared.root) -> URL {
        let digest = SHA256.hash(data: Data(artist.precomposedStringWithCanonicalMapping.utf8)).map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent("ArtistPhotos", isDirectory: true).appendingPathComponent(digest + ".image")
    }
    static func choose(for artist: String, completion: @escaping () -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let source = panel.url else { return }
            let destination = url(for: artist)
            Task {
                let success = await Task.detached(priority: .utility) {
                    let access = source.startAccessingSecurityScopedResource()
                    defer { if access { source.stopAccessingSecurityScopedResource() } }
                    do {
                        let data = try Data(contentsOf: source)
                        guard ArtworkRendering.thumbnail(data, maximum: 320) != nil else { return false }
                        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try data.write(to: destination, options: .atomic)
                        return true
                    } catch { return false }
                }.value
                if success { completion() }
            }
        }
    }
}
struct ArtistPortrait: View {
    let name: String
    let revision: Int
    var active = true
    @State private var image: NSImage?
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFill() }
            else { Image(systemName: "person.crop.square.fill").resizable().scaledToFit().foregroundStyle(.secondary).padding(24) }
        }
        .task(id: "\(active)-\(name)-\(revision)") {
            guard active else { image = nil; return }
            let path = ArtistPortraitStorage.url(for: name)
            let bitmap = await Task.detached(priority: .utility) {
                guard let data = try? Data(contentsOf: path, options: .mappedIfSafe) else { return nil as CGImage? }
                return ArtworkRendering.thumbnail(data, maximum: 320)
            }.value
            guard !Task.isCancelled else { return }
            image = bitmap.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
        }
    }
}
