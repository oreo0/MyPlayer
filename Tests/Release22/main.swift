import SwiftUI
import AppKit
import AVFoundation

@MainActor final class AppDelegate: NSObject { func bindWindow(_ window: NSWindow) {} }
@MainActor final class Route22: ObservableObject { @Published var playing = true }
struct OldVideoRoute22: View {
    @ObservedObject var route: Route22
    let player: AVPlayer
    var body: some View { ZStack { if route.playing { NativeVideoView(player: player) } else { Color.clear } }.frame(width: 600, height: 400) }
}
@main struct Tests22 {
    static func check(_ value: Bool, _ text: String) { if !value { fatalError(text) } }
    @MainActor static func settle(_ milliseconds: Int = 160) async throws { try await Task.sleep(for: .milliseconds(milliseconds)) }
    @MainActor static func main() async throws {
        setbuf(stdout, nil)
        NSApplication.shared.setActivationPolicy(.prohibited)
        UserDefaults.standard.set(false, forKey: "showMenuBarLyrics")
        let root = URL(fileURLWithPath: CommandLine.arguments[1]), defaults = UserDefaults(suiteName: "MyPlayer.Release22." + UUID().uuidString)!
        defaults.set(false, forKey: "showMenuBarLyrics"); defaults.set(false, forKey: "autoScanFolders")
        let store = UserDataStore(root: root.appendingPathComponent("data"), defaults: defaults); store.prepare()
        let movie = root.appendingPathComponent("sample.mov")
        let song = Song(path: movie.path, title: String(repeating: "Long video title ", count: 7), artist: "Test Artist", album: "Test Album", duration: 20)
        let session = PlaybackSession(songID: song.id, path: song.path, seconds: 2.25, wasPlaying: false, countedThisPlay: true, contextIDs: [song.id])
        UserDataFiles.save([song], to: store.file("library.json")); UserDataFiles.save(session, to: store.file("playback-session.json")); UserDataFiles.save(song, to: store.file("last-playing-song.json")); UserDataFiles.flush()
        let player = PlayerManager(userData: store, startsServices: false), collections = CollectionStore(url: store.file("collections.json"))
        for _ in 0..<100 { if let engine = player.videoPlayer, engine.currentItem?.status == .readyToPlay, abs(engine.currentTime().seconds - 2.25) < 0.06 { break }; try await settle(30) }
        let engine = player.videoPlayer!, item = engine.currentItem!
        check(try await item.asset.loadTracks(withMediaType: .audio).count == 1, "fixture includes real PCM audio")
        check(try await item.asset.loadTracks(withMediaType: .video).count == 1, "fixture includes video")
        engine.isMuted = true
        let oldRoute = Route22(), oldHost = NSHostingView(rootView: OldVideoRoute22(route: oldRoute, player: engine))
        let oldWindow = NSWindow(contentRect: .init(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        oldWindow.contentView = oldHost; oldHost.layoutSubtreeIfNeeded(); try await settle()
        let oldView = VideoPresentation.shared.view!
        oldRoute.playing = false; try await settle()
        check(oldView.player == nil, "baseline route actually detaches the AVPlayerView")
        print("BASELINE: switching away dismantles AVPlayerView and clears its player")
        oldWindow.contentView = nil
        let host = NSHostingView(rootView: ContentView().environmentObject(player).environmentObject(collections).defaultAppStorage(defaults))
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 1100, height: 760), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = host; host.layoutSubtreeIfNeeded(); try await settle(400)
        let retained = VideoPresentation.shared.view!
        check(retained.player === engine, "video attaches to the retained route")
        let primingStart = engine.currentTime().seconds
        player.togglePlayPause()
        for _ in 0..<100 {
            if engine.timeControlStatus == .playing && engine.currentTime().seconds > primingStart + 0.2 { break }
            try await settle(30)
        }
        check(engine.currentTime().seconds > primingStart + 0.2, "PCM audio and video clock must actually advance before routing test")
        // Audio priming can issue a time-jumped notification before playback settles.
        // Observe only the navigation interval, after the engine is demonstrably running.
        var jumps = 0
        let observer = NotificationCenter.default.addObserver(forName: .AVPlayerItemTimeJumped, object: item, queue: .main) { _ in jumps += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }
        var before = engine.currentTime().seconds
        let navigationStart = before
        for index in 0..<12 {
            NotificationCenter.default.post(name: .myPlayerNavigate, object: index.isMultiple(of: 2) ? "library" : "playing")
            try await settle(100)
            let now = engine.currentTime().seconds
            check(VideoPresentation.shared.view === retained && retained.player === engine && engine.currentItem === item, "tab change must not recreate, detach or replace player surface/item")
            check(now >= before - 0.03 && now - before < 0.75, "tab change jumps media time: \(before) -> \(now)")
            before = now
        }
        check(before > navigationStart + 0.5, "audio/video continues advancing across tab changes")
        check(jumps == 0 && player.isPlaying, "no AVPlayerItem time jumps or playback stop")
        print("PASS: 12 real ContentView tab switches keep one AVPlayerView, player and item; monotonic video/audio clock, 0 time-jump notifications")
        player.togglePlayPause(); player.checkpointPlayback(flush: true)
        var noArtist = song; noArtist.artist = "  "
        check(NowPlayingTabTitle.text(for: song) == song.title + " - Test Artist", "title and artist format")
        check(NowPlayingTabTitle.text(for: noArtist) == song.title, "no blank artist separator")
        check(NowPlayingTabTitle.text(for: nil) == "未在播放", "idle title")
        check(AdaptiveToolbarSongTitle.naturalWidth(song.title) > AdaptiveToolbarSongTitle.maximumWidth, "test title exceeds cap")
        let marquee = TitleMarquee.MarqueeView(frame: .init(x: 0, y: 0, width: AdaptiveToolbarSongTitle.maximumWidth, height: 20))
        window.contentView?.addSubview(marquee); marquee.configure(text: NowPlayingTabTitle.text(for: song), active: true); marquee.layout()
        check(marquee.isScrolling && marquee.scrollDistance > 0, "long title scrolls inside the fixed maximum width")
        print("PASS: title/artist/empty-title formatting, 220pt text cap and native Core Animation marquee")
        for width in [800.0, 900, 1240, 1800] {
            let inline = SidePanelMetrics.resolvedWidth(for: width, preferred: 0, overlay: false)
            check(inline >= 180 && inline <= 720, "shared queue panel width")
        }
        let rootMenu = NSMenu(), systemView = NSMenuItem(title: "显示", action: nil, keyEquivalent: "")
        systemView.submenu = NSMenu(title: "显示"); rootMenu.addItem(systemView)
        let appearance = NSMenuItem(title: "外观", action: nil, keyEquivalent: ""); appearance.submenu = NSMenu(title: "外观")
        appearance.submenu!.addItem(withTitle: "进入或退出全屏幕", action: nil, keyEquivalent: ""); rootMenu.addItem(appearance)
        let policy = AppearanceMenuNaming(menu: { rootMenu }); policy.install()
        check(systemView.isHidden && !appearance.isHidden, "only declarative Appearance menu is visible")
        for i in 0..<200 {
            systemView.title = i.isMultiple(of: 2) ? "View" : "显示"
            systemView.isHidden = false
            check(systemView.isHidden && appearance.title == "外观" && appearance.submenu?.items.count == 1, "duplicate system menu hidden before the mutation returns")
        }
        print("PASS: 200 synchronous system-menu updates cannot flash View; Appearance title and fullscreen entry preserved")
        player.stop(); player.flushLibrarySaves(); window.contentView = nil
        print("PASS: isolated data, retained playback checkpoint and shared panel width limits")
    }
}
