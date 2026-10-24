import Foundation
import AppKit
import AVFoundation

@MainActor final class AppDelegate: NSObject {
    func bindWindow(_ window: NSWindow) {}
}

@main struct SessionTests {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MyPlayer-session-" + UUID().uuidString)
        let suite = "MyPlayer.Test." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let store = UserDataStore(root: root, defaults: defaults)
        store.prepare()
        let wav = root.appendingPathComponent("sample.wav")
        // 20 seconds of silence, no audio output needed for paused restoration.
        let samples = 20 * 8000 * 2
        var bytes = Data()
        func text(_ value: String) { bytes.append(contentsOf: value.utf8) }
        func u32(_ value: UInt32) { var v = value.littleEndian; withUnsafeBytes(of: &v) { bytes.append(contentsOf: $0) } }
        func u16(_ value: UInt16) { var v = value.littleEndian; withUnsafeBytes(of: &v) { bytes.append(contentsOf: $0) } }
        text("RIFF"); u32(UInt32(36 + samples)); text("WAVEfmt "); u32(16); u16(1); u16(1)
        u32(8000); u32(16000); u16(2); u16(16); text("data"); u32(UInt32(samples)); bytes.append(Data(count: samples))
        try bytes.write(to: wav)
        let song = Song(path: wav.path, title: "持久化测试", artist: "测试", album: "测试", duration: 20)
        let context = [song.id, UUID()]
        let original = PlaybackSession(songID: song.id, path: song.path, seconds: 7.25, wasPlaying: false,
                                       countedThisPlay: true, contextIDs: context)
        UserDataFiles.save([song], to: store.file("library.json"))
        UserDataFiles.save(song, to: store.file("last-playing-song.json"))
        UserDataFiles.save(original, to: store.file("playback-session.json")); UserDataFiles.flush()
        let player = PlayerManager(userData: store, startsServices: false)
        precondition(player.nowPlaying?.id == song.id, "restore song identity")
        precondition(abs(player.currentTime - 7.25) < 0.03, "restore paused audio position")
        precondition(!player.isPlaying, "preserve pause")
        player.seek(to: 12.5)
        player.checkpointPlayback(flush: true)
        let saved = try JSONDecoder().decode(PlaybackSession.self, from: Data(contentsOf: store.file("playback-session.json")))
        precondition(abs(saved.seconds - 12.5) < 0.03 && saved.contextIDs == context)
        let second = PlayerManager(userData: store, startsServices: false)
        precondition(second.nowPlaying?.id == song.id && abs(second.currentTime - 12.5) < 0.03, "restore after replacement/relaunch")
        second.stop(); UserDataFiles.flush()
        let stopped = PlayerManager(userData: store, startsServices: false)
        precondition(stopped.nowPlaying == nil, "explicit removal must not resurrect media")
        // Restore a real video with a nonzero seek before playback starts.
        let movie = root.appendingPathComponent("sample.mov")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: CommandLine.arguments[1]), to: movie)
        let video = Song(path: movie.path, title: "视频恢复", artist: "", album: "", duration: 20)
        let videoSession = PlaybackSession(songID: video.id, path: video.path, seconds: 8.4, wasPlaying: false, countedThisPlay: true, contextIDs: nil)
        UserDataFiles.save(video, to: store.file("last-playing-song.json"))
        UserDataFiles.save(videoSession, to: store.file("playback-session.json")); UserDataFiles.flush()
        let videoPlayer = PlayerManager(userData: store, startsServices: false)
        for _ in 0..<100 {
            if abs((videoPlayer.videoPlayer?.currentTime().seconds ?? 0) - 8.4) < 0.05 { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        precondition(videoPlayer.isVideo && !videoPlayer.isPlaying)
        precondition(abs((videoPlayer.videoPlayer?.currentTime().seconds ?? 0) - 8.4) < 0.05, "restore video engine time, not only UI label")
        videoPlayer.checkpointPlayback(flush: true)
        let videoSaved = try JSONDecoder().decode(PlaybackSession.self, from: Data(contentsOf: store.file("playback-session.json")))
        precondition(videoSaved.songID == video.id && abs(videoSaved.seconds - 8.4) < 0.05)
        videoPlayer.stop(); UserDataFiles.flush()
        precondition(original.position(limitedTo: 5) == 5)
        print("PASS: real video seek + audio restore, paused position, seek checkpoint, context order, relaunch, explicit stop")
    }
}
