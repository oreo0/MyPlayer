import SwiftUI
import AppKit
@MainActor final class AppDelegate: NSObject { func bindWindow(_ window: NSWindow) {} }
@main struct Catalog52Tests {
    @MainActor static func main() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        func song(_ title: String, album: String) -> Song { Song(path: "/media/\(title).mp3", title: title, artist: "Artist", album: album, duration: 10) }
        let songs = [song("张三",album:"上海"),song("Bob",album:"北京"),song("陈红",album:"广州"),song("Alice",album:"Apple")]
        let asc = try MediaCoverOrdering.build(songs, grouping: .album, ascending: true)
        precondition(asc.map(\.title) == ["Apple","北京","广州","上海"])
        let desc = try MediaCoverOrdering.build(songs, grouping: .album, ascending: false)
        precondition(desc.map(\.title) == Array(asc.map(\.title).reversed()))
        let artists = try MediaCoverOrdering.build(songs, grouping: .artist, ascending: true)
        precondition(artists[0].songs.map(\.title) == ["Alice","Bob","陈红","张三"])
        let numeric = try MediaCoverOrdering.sorted(["Album 10","Album 2"],ascending:true,title:{$0})
        let ties = try MediaCoverOrdering.sorted(["Écho","Echo","echo"],ascending:false,title:{$0})
        precondition(numeric == ["Album 2","Album 10"])
        precondition(ties == ["Écho","Echo","echo"])
        let catalog = CoverCatalog()
        catalog.update(songs, grouping: .album, ascending: true)
        for _ in 0..<300 { if catalog.groups.count == 4 { break }; try await Task.sleep(for: .milliseconds(10)) }
        precondition(catalog.groups.map(\.title) == asc.map(\.title))
        for _ in 0..<2000 { catalog.update(songs, grouping: .album, ascending: true) }
        precondition(catalog.rebuilds == 1, "selection/hover redraws cannot rebuild groups or pinyin keys")
        catalog.suspend(); catalog.update(songs,grouping:.album,ascending:true)
        precondition(catalog.rebuilds == 1, "completed cache survives tab/view switches")
        let many = (0..<2000).map { song("Track \($0)", album:"Album \($0)") }
        catalog.update(many,grouping:.album,ascending:true)
        catalog.suspend()
        catalog.update([songs[0]],grouping:.artist,ascending:false)
        for _ in 0..<300 { if catalog.groups.count == 1 && catalog.groups.first?.kind == .artist { break }; try await Task.sleep(for: .milliseconds(10)) }
        precondition(catalog.groups.count == 1 && catalog.groups.first?.kind == .artist)
        precondition(catalog.groups.first?.songs.first?.id == songs[0].id, "discard cancelled/stale results")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Catalog52-\(UUID().uuidString)")
        let suite = "MyPlayer.Catalog52.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName:suite); try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root,withIntermediateDirectories:true)
        let data = try PropertyListSerialization.data(fromPropertyList:["coverSortAscending":false],format:.binary,options:0)
        try data.write(to:root.appendingPathComponent("preferences.plist"))
        let store = UserDataStore(root:root,defaults:defaults); store.prepare()
        precondition(defaults.object(forKey:"coverSortAscending") as? Bool == false)
        print("PASS: pinyin/Latin/numeric sorting, stable equal keys, cached 2,000 redraw requests, cancellation/latest result, view-switch cache reuse and sort preference restore")
    }
}
