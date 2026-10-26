import Foundation
import AppKit
import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

@MainActor final class AppDelegate: NSObject { func bindWindow(_ window: NSWindow) {} }
@main struct Release21Tests {
    static func check(_ value: Bool, _ message: String) { if !value { fatalError(message) } }
    static func mediaPackets(_ url: URL) async throws -> [Data] {
        let ext = url.pathExtension.lowercased(), data = try Data(contentsOf: url)
        if ext == "mp3" {
            let start = data.prefix(3) == Data("ID3".utf8) ? try SourceTagCodec.syncNumber(data, 6) + 10 : 0
            let end = data.count >= 128 && data.suffix(128).prefix(3) == Data("TAG".utf8) ? data.count - 128 : data.count
            return [Data(data[start..<end])]
        }
        if ext == "mov" {
            var cursor = 0
            while cursor + 8 <= data.count {
                var size = Int(try SourceTagCodec.number(data, cursor, 4)), header = 8
                if size == 1 { size = Int(try SourceTagCodec.number(data, cursor + 8, 8)); header = 16 }
                if size == 0 { size = data.count - cursor }
                guard size >= header, cursor + size <= data.count else { fatalError("invalid movie atom") }
                if String(decoding: data[cursor + 4..<cursor + 8], as: UTF8.self) == "mdat" { return [Data(data[cursor + header..<cursor + size])] }
                cursor += size
            }
            fatalError("missing movie media payload")
        }
        if ext == "flac" {
            var cursor = 4, last = false
            while !last { last = data[cursor] & 128 != 0; cursor += 4 + Int(try SourceTagCodec.number(data, cursor + 1, 3)) }
            return [Data(data.dropFirst(cursor))]
        }
        if ["wav", "aiff"].contains(ext) {
            var cursor = 12
            while cursor + 8 <= data.count {
                let count = Int(try SourceTagCodec.number(data, cursor + 4, 4, little: ext == "wav"))
                let id = String(decoding: data[cursor..<cursor + 4], as: UTF8.self)
                if id == (ext == "wav" ? "data" : "SSND") { return [Data(data[cursor + 8..<cursor + 8 + count])] }
                cursor += 8 + count + (count & 1)
            }
            fatalError("missing audio payload")
        }
        let asset = AVURLAsset(url: url), reader = try AVAssetReader(asset: asset)
        let tracks = try await asset.load(.tracks)
        let outputs = tracks.map { AVAssetReaderTrackOutput(track: $0, outputSettings: nil) }
        for output in outputs { reader.add(output) }
        guard reader.startReading() else { throw reader.error! }
        var packets = [Data](repeating: Data(), count: outputs.count)
        for (index, output) in outputs.enumerated() {
            while let sample = output.copyNextSampleBuffer() {
                guard let buffer = CMSampleBufferGetDataBuffer(sample) else { continue }
                let size = CMBlockBufferGetDataLength(buffer); var bytes = Data(count: size)
                let status = bytes.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(buffer, atOffset: 0, dataLength: size, destination: $0.baseAddress!) }
                check(status == noErr, "read media packets"); packets[index].append(bytes)
            }
        }
        check(packets.allSatisfy { !$0.isEmpty }, "nonempty packet payloads")
        check(reader.status == .completed, "complete packet read \(url.lastPathComponent): \(String(describing: reader.error))")
        return packets
    }
    @MainActor static func main() async throws {
        setbuf(stdout, nil)
        NSApplication.shared.setActivationPolicy(.prohibited)
        let root = URL(fileURLWithPath: CommandLine.arguments[1]), fm = FileManager.default
        let suite = "MyPlayer.Release21." + UUID().uuidString, defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let userRoot = root.appendingPathComponent("UserData"), store = UserDataStore(root: userRoot, defaults: defaults)
        defaults.set(42.0, forKey: "lyricsFontSize"); store.prepare()
        for c in LyricsSizeContext.allCases { check(defaults.double(forKey: c.key) == 42, "migrate legacy lyric size") }
        defaults.set(28.0, forKey: LyricsSizeContext.sidebar.key); defaults.set(36.0, forKey: LyricsSizeContext.windowed.key); defaults.set(64.0, forKey: LyricsSizeContext.fullscreen.key)
        LyricsFontSizes.migrate(defaults); store.flush()
        check(LyricsSizeContext.allCases.map { defaults.double(forKey: $0.key) } == [28, 36, 64], "independent lyric values")
        let prefData = try Data(contentsOf: store.file("preferences.plist")); let prefValues = try PropertyListSerialization.propertyList(from: prefData, format: nil) as! [String: Any]; let prefText = prefValues.keys.joined(separator: ",")
        check(LyricsSizeContext.allCases.allSatisfy { prefText.contains($0.key) }, "cloud preference snapshot includes three sizes")
        print("PASS: legacy lyric migration, independent settings and preference snapshot")

        let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 24, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 128, bitsPerPixel: 32)!
        let cover = image.representation(using: .png, properties: [:])!
        let tags = SourceMediaMetadata(title: "测试标题", artist: "测试艺人", album: "测试专辑", artwork: cover)
        let backupRoot = root.appendingPathComponent("backups")
        for ext in ["mp3", "flac", "wav", "aiff", "m4a", "mp4", "mov"] {
            let source = root.appendingPathComponent("source." + ext), digest = try SourceMediaEditor.digest(source)
            let before = try await mediaPackets(source)
            let result = try await SourceMediaEditor.write(source, metadata: tags, backupRoot: backupRoot)
            check(result.url.lastPathComponent == "测试标题 - 测试艺人." + ext && !fm.fileExists(atPath: source.path), "rename \(ext)")
            check(try SourceMediaEditor.digest(result.backup) == digest, "exact original backup \(ext)")
            let loaded = Song.load(at: result.url)
            check(loaded?.title == tags.title && loaded?.artist == tags.artist && loaded?.album == tags.album && loaded?.artworkData == cover, "source metadata reimport \(ext)")
            let after = try await mediaPackets(result.url)
            check(before == after, "compressed media packets must remain byte-identical \(ext)")
            let asset = AVURLAsset(url: result.url), meta = try await asset.load(.commonMetadata)
            if ext == "flac" {
                let native = AudioFileMetadata.read(result.url)
                check(native?.title == tags.title && native?.artist == tags.artist && native?.album == tags.album && native?.artwork == cover, "Core Audio FLAC tags and picture")
                let reimported = Song.load(at: result.url)
                check(reimported?.title == tags.title && reimported?.artist == tags.artist && reimported?.album == tags.album && reimported?.artworkData == cover, "FLAC reimport retains edits")
            } else {
            for (key, expected) in zip([AVMetadataKey.commonKeyTitle, .commonKeyArtist, .commonKeyAlbumName], [tags.title, tags.artist, tags.album]) {
                let values = meta.filter { $0.commonKey == key }.compactMap(\.stringValue)
                check(values.contains(expected), "native tag roundtrip \(ext) \(key): \(values)")
            }
            check(meta.contains { $0.commonKey == .commonKeyArtwork && $0.dataValue == cover }, "native artwork roundtrip \(ext)")
            }
            let withoutCover = SourceMediaMetadata(title: tags.title, artist: tags.artist, album: tags.album, artwork: nil)
            let removed = try await SourceMediaEditor.write(result.url, metadata: withoutCover, backupRoot: backupRoot)
            let meta2 = try await AVURLAsset(url: removed.url).load(.commonMetadata)
            check(!meta2.contains { $0.commonKey == .commonKeyArtwork } && AudioFileMetadata.read(removed.url)?.artwork == nil, "remove cover \(ext)")
            print("PASS: \(ext) Unicode metadata + cover write/remove, rename, exact backup and unchanged media packets")
        }
        let existing = root.appendingPathComponent("测试标题 - 测试艺人.wav")
        let source = root.appendingPathComponent("collision.wav"); try fm.copyItem(at: existing, to: source)
        let originalDigest = try SourceMediaEditor.digest(source)
        do { _ = try await SourceMediaEditor.write(source, metadata: tags, backupRoot: backupRoot); fatalError("collision must fail") } catch SourceMediaError.collision {}
        check(try SourceMediaEditor.digest(source) == originalDigest, "collision original unchanged")
        let bad = root.appendingPathComponent("bad.mp3"); try Data("bad".utf8).write(to: bad)
        do { _ = try await SourceMediaEditor.write(bad, metadata: tags, backupRoot: backupRoot); fatalError("corrupt file must fail") } catch {}
        check(try Data(contentsOf: bad) == Data("bad".utf8), "corrupt original unchanged")
        let aac = root.appendingPathComponent("unsupported.aac"); try Data("test".utf8).write(to: aac)
        do { _ = try await SourceMediaEditor.write(aac, metadata: tags, backupRoot: backupRoot); fatalError("unsupported must fail") } catch SourceMediaError.unsupported {}
        check(try Data(contentsOf: aac) == Data("test".utf8), "unsupported original unchanged")
        print("PASS: collision, malformed and unsupported files preserve originals")

        // Unknown ID3 frames survive an edit, including a v2.4 unsynchronised frame.
        let unknown = SourceTagCodec.Frame(id: "TXXX", flags: 0, body: Data([3]) + Data("custom\0value".utf8))
        let originalTag = Data("ID3".utf8) + Data([4, 0, 0]) + SourceTagCodec.syncSize(unknown.body.count + 10) + Data(unknown.id.utf8) + SourceTagCodec.syncSize(unknown.body.count) + Data([0, 0]) + unknown.body
        let parsed = try SourceTagCodec.frames(SourceTagCodec.id3(tags, original: originalTag))
        check(parsed.version == 4 && parsed.frames.contains { $0.id == unknown.id && $0.body == unknown.body }, "retain unrelated v2.4 ID3 tags")
        check(try SourceMediaEditor.filename(title: "a/b:c", artist: "d", extension: "mp3") == "a_b_c - d.mp3", "sanitize file names")
        let player = PlayerManager(userData: store, startsServices: false)
        let importFolder = root.appendingPathComponent("imports"); try fm.createDirectory(at: importFolder, withIntermediateDirectories: true)
        var urls: [URL] = []
        for name in ["Zulu", "Alpha", "Middle"] {
            let u = importFolder.appendingPathComponent(name + ".wav"); try fm.copyItem(at: source, to: u)
            let tag = SourceMediaMetadata(title: name, artist: "Test", album: "Album", artwork: cover)
            let tagged = try await SourceMediaEditor.write(u, metadata: tag, backupRoot: backupRoot); urls.append(tagged.url)
        }
        func waitForCount(_ count: Int) async throws {
            for _ in 0..<150 { if player.library.count == count && player.libraryActivity == nil { return }; try await Task.sleep(for: .milliseconds(30)) }
            fatalError("import timed out")
        }
        player.importDroppedMedia([urls[0], urls[1]]); try await waitForCount(2)
        player.sortLibrary(using: [KeyPathComparator(\Song.title)])
        // The drop bridge accepts Finder's file URL data and deduplicates providers.
        let item = NSItemProvider(item: urls[2] as NSURL, typeIdentifier: UTType.fileURL.identifier)
        var dropCompleted = false
        check(FileDropImporter.receive([item, item]) { values in check(values == [urls[2]], "drop URL and dedupe"); player.importDroppedMedia(values); dropCompleted = true }, "accept file URL drop")
        try await waitForCount(3); check(dropCompleted, "drop completion")
        check(player.sortedLibrary.map(\.title) == ["Alpha", "Middle", "Zulu"], "import respects active A-Z column sort")
        player.sortLibrary(using: [KeyPathComparator(\Song.title, order: .reverse)])
        check(player.sortedLibrary.map(\.title) == ["Zulu", "Middle", "Alpha"], "descending sort")
        player.flushLibrarySaves(); store.flush()
        let restored = PlayerManager(userData: store, startsServices: false)
        check(restored.sortedLibrary.map(\.title) == ["Zulu", "Middle", "Alpha"], "restore sort descriptor after relaunch")
        player.sortKey = .artist
        check(!player.usesCustomLibraryOrder, "menu sort exits previous table sort")
        player.sortKey = .title; player.sortAscending = true
        let song = player.library.first { $0.title == "Middle" }!
        player.enqueue(song); player.play(song); player.togglePlayPause(); player.seek(to: 1.25)
        let lrc = song.autoLrcURL; try Data("[00:00.00]Test".utf8).write(to: lrc)
        try await player.editSourceMetadata(song, title: "Bravo", artist: "Test", album: "Album", artwork: cover)
        for _ in 0..<100 { if abs(player.currentTime - 1.25) < 0.05 && !player.isPlaying { break }; try await Task.sleep(for: .milliseconds(30)) }
        let updated = player.library.first { $0.id == song.id }!
        check(updated.url.lastPathComponent == "Bravo - Test.wav" && updated.lyricsPath == lrc.path, "rename retains identity and linked sidecar")
        check(player.upNext.contains(song.id) && player.nowPlaying?.path == updated.path && !player.isPlaying && abs(player.currentTime - 1.25) < 0.05, "rename preserves queue and paused playback")
        check(player.sortedLibrary.map(\.title) == ["Alpha", "Bravo", "Zulu"], "metadata edit reorders active sort")
        player.checkpointPlayback(flush: true); player.flushLibrarySaves()
        let checkpoint = try JSONDecoder().decode(PlaybackSession.self, from: Data(contentsOf: store.file("playback-session.json")))
        check(checkpoint.path == updated.path && checkpoint.songID == song.id, "renamed playback checkpoint")
        check(!player.sourceFileBackupRoot.path.hasPrefix(store.root.path + "/"), "original media backups excluded from cloud user data")
        player.stop(); restored.stop()
        print("PASS: Finder drop, dedupe, queued imports, immediate sort, descriptor persistence, rename identity/queue/lyrics/playback")

        let bounds = CGRect(x: 0, y: 0, width: 900, height: 600)
        for point in [CGPoint(x: 0, y: 300), CGPoint(x: 899, y: 300), CGPoint(x: 400, y: 1), CGPoint(x: 400, y: 599), CGPoint(x: 1, y: 1)] { check(ResizeBoundary.contains(point, in: bounds), "native resize edge pass-through") }
        check(!ResizeBoundary.contains(CGPoint(x: 450, y: 300), in: bounds), "canvas still receives interior clicks")
        let window = NSWindow(contentRect: bounds, styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        let interaction = WindowInteraction.InteractionView(frame: bounds)
        window.contentView?.addSubview(interaction)
        interaction.onCanvasClick = { !ResizeBoundary.contains($0, in: CGRect(origin: .zero, size: window.frame.size)) }
        check(!interaction.handleCanvasMouseDown(at: CGPoint(x: 2, y: 200), in: window), "native monitor must return edge event to AppKit")
        check(interaction.handleCanvasMouseDown(at: CGPoint(x: 450, y: 200), in: window), "native monitor keeps canvas interaction")
        let menu = NSMenu(), appearance = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        appearance.submenu = NSMenu(title: "View"); let child = appearance.submenu!.addItem(withTitle: "Full Screen", action: nil, keyEquivalent: "f"); menu.addItem(appearance)
        let custom = NSMenuItem(title: "外观", action: nil, keyEquivalent: ""); menu.addItem(custom)
        let naming = AppearanceMenuNaming(menu: { menu }); naming.install()
        check(appearance.isHidden && custom.title == "外观" && appearance.submenu!.items.contains(child), "rename menu without losing entries")
        appearance.title = "显示"
        try await Task.sleep(for: .milliseconds(80))
        check(appearance.isHidden && custom.title == "外观", "keep appearance title after SwiftUI recreation")
        print("PASS: four resize edges/corners, canvas interior, native appearance menu recreation")
    }
}
