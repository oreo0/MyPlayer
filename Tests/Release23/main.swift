import SwiftUI
import AppKit
import AVFoundation
import Combine

@MainActor final class AppDelegate: NSObject { func bindWindow(_ window: NSWindow) {} }
@MainActor final class EditorModel23: ObservableObject { @Published var show = false }
struct EditorHarness23: View {
    @ObservedObject var editor: EditorModel23
    let player: PlayerManager
    let collections: CollectionStore
    let defaults: UserDefaults
    var body: some View {
        ContentView().environmentObject(player).environmentObject(collections).defaultAppStorage(defaults)
            .sheet(isPresented: $editor.show) { MediaInfoEditor(song: player.nowPlaying!).environmentObject(player) }
    }
}
@main struct Tests23 {
    static func check(_ condition: Bool, _ message: String) { if !condition { fatalError(message) } }
    @MainActor static func wait(_ milliseconds: Int = 100) async throws { try await Task.sleep(for: .milliseconds(milliseconds)) }
    @MainActor static func main() async throws {
        setbuf(stdout, nil)
        NSApplication.shared.setActivationPolicy(.accessory)
        UserDefaults.standard.set(false, forKey: "showMenuBarLyrics")
        let root = URL(fileURLWithPath: CommandLine.arguments[1]), suite = "MyPlayer.Test23." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "showMenuBarLyrics"); defaults.set(false, forKey: "autoScanFolders")
        defaults.set("blue", forKey: "themeColorName")
        let store = UserDataStore(root: root.appendingPathComponent("data"), defaults: defaults); store.prepare()
        let song = Song(path: root.appendingPathComponent("sample.mov").path, title: "Editor and Loop", artist: "Test", album: "Local", duration: 20)
        let session = PlaybackSession(songID: song.id, path: song.path, seconds: 0.5, wasPlaying: false, countedThisPlay: true, contextIDs: [song.id])
        UserDataFiles.save([song], to: store.file("library.json")); UserDataFiles.save(song, to: store.file("last-playing-song.json")); UserDataFiles.save(session, to: store.file("playback-session.json")); UserDataFiles.flush()
        let player = PlayerManager(userData: store, startsServices: false), collections = CollectionStore(url: store.file("collections.json"))
        for _ in 0..<100 { if player.videoPlayer?.currentItem?.status == .readyToPlay && abs((player.videoPlayer?.currentTime().seconds ?? 0) - 0.5) < 0.07 { break }; try await wait(30) }
        let engine = player.videoPlayer!, item = engine.currentItem!; engine.isMuted = true
        let editor = EditorModel23()
        let host = NSHostingView(rootView: EditorHarness23(editor: editor, player: player, collections: collections, defaults: defaults))
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 1100, height: 760), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = host; window.setFrameOrigin(NSPoint(x: 40, y: 40)); window.orderFront(nil); host.layoutSubtreeIfNeeded(); try await wait(350)
        let surface = VideoPresentation.shared.view!
        check(!surface.allowsVideoFrameAnalysis, "custom context menu must not trigger AVKit frame analysis")
        player.togglePlayPause()
        for _ in 0..<100 { if engine.timeControlStatus == .playing && engine.currentTime().seconds > 0.7 { break }; try await wait(30) }
        let beforeSheet = engine.currentTime().seconds
        editor.show = true; try await wait(450)
        check(InteractionActivity.shared.isEditingMetadata && MetadataShortcutScope.shared.isEditing, "metadata sheet owns transport keyboard input")
        check(!PlaybackKeyboardScope.permitsTransport(in: window), "parent shortcuts must not steal sheet arrows/space")
        print("SHEET", beforeSheet, engine.currentTime().seconds, engine.rate, player.isPlaying, VideoPresentation.shared.view === surface, surface.player === engine)
        check(engine.rate != 0 && engine.currentTime().seconds > beforeSheet + 0.05 && VideoPresentation.shared.view === surface && surface.player === engine, "sheet must not pause or detach video")
        let sheetTime = engine.currentTime().seconds
        try await wait(650)
        check(engine.currentTime().seconds > sheetTime + 0.4 && player.isPlaying, "video/audio advance while editing")
        editor.show = false
        for _ in 0..<100 { if !InteractionActivity.shared.isEditingMetadata { break }; try await wait(30) }
        print("DISMISS", editor.show, window.attachedSheet as Any, InteractionActivity.shared.isEditingMetadata)
        check(!InteractionActivity.shared.isEditingMetadata && !MetadataShortcutScope.shared.isEditing, "editor shortcut state is released")
        print("PASS: real metadata sheet keeps video/audio running, retains AVPlayerView, and disables transport key capture until dismissed")

        player.togglePlayPause(); let pausedTime = engine.currentTime().seconds
        editor.show = true; try await wait(650)
        check(engine.rate == 0 && abs(engine.currentTime().seconds - pausedTime) < 0.08, "previously paused video stays paused in editor")
        editor.show = false
        for _ in 0..<100 { if !InteractionActivity.shared.isEditingMetadata { break }; try await wait(30) }
        check(!MetadataShortcutScope.shared.isEditing && engine.rate == 0, "paused editor dismissal releases shortcuts without playing")
        player.togglePlayPause()
        print("PASS: previously paused video remains paused during and after metadata editing")

        // Exercise actual end-of-item notifications repeatedly, keeping the decoder and view attached.
        player.repeatMode = .repeatOne; item.forwardPlaybackEndTime = CMTime(seconds: 2.0, preferredTimescale: 600)
        player.seek(to: 0)
        let frames = AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        item.add(frames)
        var ended = 0
        let endToken = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { _ in ended += 1 }
        defer { NotificationCenter.default.removeObserver(endToken); item.remove(frames) }
        var lastEnd = 0, iterationsWithImage = Set<Int>()
        for _ in 0..<320 {
            try await wait(30)
            check(player.videoPlayer === engine && engine.currentItem === item && surface.player === engine, "loop must not replace engine/item/surface binding")
            let time = engine.currentTime()
            if let pixels = frames.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil), CVPixelBufferGetWidth(pixels) > 0 { iterationsWithImage.insert(ended) }
            if ended >= 3 && time.seconds > 0.25 && engine.rate != 0 { break }
            if ended != lastEnd { print("LOOP", ended, "same player/item/view"); lastEnd = ended }
        }
        check(ended >= 3 && iterationsWithImage.contains(1) && iterationsWithImage.contains(2), "second and third playback iterations must decode real video frames")
        check(engine.rate != 0 && player.isPlaying, "loop resumes playback")
        player.togglePlayPause(); try await wait(80)
        check(engine.rate == 0 && !player.isPlaying, "explicit pause after looping remains paused")
        print("PASS: three real repeat-one EOF cycles, frames decoded in later cycles, identical player/item/view, explicit pause preserved")

        let activity = InteractionActivity(observesMenus: false), parent = NSMenu(), child = NSMenu()
        let observer = MenuPlayerObserver(player: player, activity: activity)
        var publishes = 0; let subscription = observer.objectWillChange.sink { publishes += 1 }
        defer { subscription.cancel() }
        activity.track(parent, began: true); activity.track(child, began: true)
        let start = publishes
        for _ in 0..<20 { player.libraryImportMessage = UUID().uuidString }
        check(publishes == start && activity.holdsAutoHide, "model updates are held while nested menus track")
        activity.track(child, began: false)
        check(activity.isTrackingMenu, "parent menu remains tracked after submenu ends")
        try await wait(5500)
        check(activity.isTrackingMenu && activity.holdsAutoHide && publishes == start, "no five-second menu timeout or rebuilding")
        activity.track(parent, began: false); try await wait(80)
        check(!activity.isTrackingMenu && publishes == start + 1, "coalesce pending menu refresh until tracking ends")
        print("PASS: nested menu tracking survives >5 seconds; player updates held and flushed exactly once after dismissal")

        let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 128, bitsPerPixel: 32)!
        let original = image.representation(using: .png, properties: [:])!, file = root.appendingPathComponent("cover.png")
        try original.write(to: file)
        check(try await CoverImageImport.file(file) == original, "Finder cover preserves original PNG bytes")
        check(try await CoverImageImport.photo(original) == original, "Photos transfer uses same verified cover pipeline")
        check(try Data(contentsOf: file) == original, "selected original image not modified")
        check(ThemeColor.current == .media && !UserDataStore.preferenceKeys.contains("themeColorName"), "legacy manual themes are ignored")
        check(MediaFilter.audio.rawValue == "歌曲" && SortKey.title.label == "文件", "only filter uses Songs; library labels unchanged")
        player.stop(); player.flushLibrarySaves(); store.flush(); window.contentView = nil
        print("PASS: Finder/Photos cover import, local preference preservation, automatic cover theme and filter-only label change")
    }
}
