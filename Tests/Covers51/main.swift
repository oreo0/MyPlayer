import SwiftUI
import AppKit
@MainActor final class AppDelegate: NSObject { func bindWindow(_ window: NSWindow) {} }
@main struct Covers51Tests {
    @MainActor static func main() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let first = Song(path: "/one/Shared/a.mp3", title: "First", artist: "Artist A", album: "Album A", duration: 20)
        let second = Song(path: "/one/Shared/b.mp4", title: "Second", artist: "Artist B", album: "Album A", duration: 20, artworkData: Data([1,2,3]))
        let third = Song(path: "/two/Shared/c.mp3", title: "Third", artist: "Artist A", album: "Album B", duration: 20)
        let fourth = Song(path: "/two/Shared/d.mp3", title: "Fourth", artist: "", album: "", duration: 20)
        let songs = [first,second,third,fourth]
        let albums = CoverGrouping.album.groups(songs)
        precondition(albums.count == 3 && albums[0].songs.map(\.id) == [first.id,second.id])
        precondition(albums[0].representative?.id == second.id, "prefer real cover, not placeholder")
        precondition(albums.last?.title == "未知专辑")
        let artists = CoverGrouping.artist.groups(songs)
        precondition(artists[0].songs.map(\.id) == [first.id,third.id])
        precondition(artists.last?.title == "未知歌手")
        let folders = CoverGrouping.folder.groups(songs)
        precondition(folders.count == 2 && folders[0].title == folders[1].title)
        precondition(folders[0].id != folders[1].id, "identical folder names at different paths stay separate")
        precondition(folders[0].songs.map(\.id) == [first.id,second.id])
        precondition(CoverGrouping.album.groups([]).isEmpty)
        precondition(CoverGrouping.album.groups([first]).first?.id == albums.first?.id)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Covers51-\(UUID().uuidString)")
        let portrait = ArtistPortraitStorage.url(for: "../../Artist A", root: root)
        precondition(portrait.deletingLastPathComponent() == root.appendingPathComponent("ArtistPhotos", isDirectory: true))
        precondition(portrait == ArtistPortraitStorage.url(for: "../../Artist A", root: root))
        let window = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 500,height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let table = NSTableView(frame: NSRect(x: 0,y: 0,width: 500,height: 400))
        window.contentView!.addSubview(table)
        let density = NativeTableDensity(table)
        // Simulate SwiftUI's final style installation, then one mount-settle pass.
        table.rowHeight = 54; table.usesAutomaticRowHeights = true
        density.enforce()
        precondition(table.rowHeight == 36 && !table.usesAutomaticRowHeights)
        table.rowHeight = 54
        try await Task.sleep(for: .milliseconds(200))
        precondition(table.rowHeight == 54, "no recurring row-height writeback")
        window.close()
        print("PASS: album/artist/folder memberships, video inclusion, stable IDs/order, real cover selection, unknown labels, safe portrait paths and bounded compact-density configuration")
    }
}
