import Foundation
import AVFoundation

// MARK: - 文件模型

struct Song: Identifiable, Codable, Hashable {
    var id: UUID
    var path: String
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var lyricsPath: String?
    var lyricsOffset: Double = 0
    var lyricsDisabled = false
    var playCount: Int
    var isFavorite: Bool
    private var storedArtwork: Data?
    private(set) var artworkPath: String?
    private(set) var artworkRevision = UUID()
    var embeddedArtwork: Data? { storedArtwork }
    var artworkID: String { "\(id)-\(artworkRevision)" }
    var hasArtwork: Bool { storedArtwork != nil || artworkPath.map { FileManager.default.fileExists(atPath: $0) } == true }
    var artworkData: Data? {
        get { storedArtwork ?? artworkPath.flatMap { try? Data(contentsOf: URL(fileURLWithPath: $0), options: .mappedIfSafe) } }
        set { storedArtwork = newValue; artworkPath = nil; artworkRevision = UUID() }
    }
    mutating func useStoredArtwork(at path: String) { artworkPath = path; storedArtwork = nil }
    mutating func relocateArtwork(root: URL) { artworkPath = ArtworkStorage.relocated(artworkPath, root: root) }
    static func == (a: Song, b: Song) -> Bool {
        a.id == b.id && a.path == b.path && a.title == b.title && a.artist == b.artist && a.album == b.album &&
        a.duration == b.duration && a.lyricsPath == b.lyricsPath && a.lyricsOffset == b.lyricsOffset &&
        a.lyricsDisabled == b.lyricsDisabled && a.playCount == b.playCount && a.isFavorite == b.isFavorite &&
        a.artworkPath == b.artworkPath && a.storedArtwork == b.storedArtwork
    }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }


    init(id: UUID = UUID(),
         path: String,
         title: String,
         artist: String,
         album: String,
         duration: TimeInterval,
         lyricsPath: String? = nil,
         playCount: Int = 0,
         isFavorite: Bool = false,
         artworkData: Data? = nil) {
        self.id = id
        self.path = path
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.lyricsPath = lyricsPath
        self.playCount = playCount
        self.isFavorite = isFavorite
        self.artworkData = artworkData
    }

    var url: URL { URL(fileURLWithPath: path) }
    /// 同目录、同名扩展名为 .lrc 的歌词文件
    var autoLrcURL: URL {
        url.deletingPathExtension().appendingPathExtension("lrc")
    }
    var autoTimedTextURL: URL? {
        ["lrc", "srt", "vtt"].map { url.deletingPathExtension().appendingPathExtension($0) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }
    var displayName: String {
        artist.isEmpty ? title : "\(title) — \(artist)"
    }

    /// 支持的视频格式（导入后走视频播放引擎）
    static let videoExtensions: Set<String> = ["mp4", "m4v", "mov"]
    var isVideo: Bool {
        Self.videoExtensions.contains(url.pathExtension.lowercased())
    }

    // 兼容旧版 library.json：新增字段缺失时给默认值
    private enum CodingKeys: String, CodingKey {
        case id, path, title, artist, album, duration
        case lyricsOffset, lyricsDisabled, lyricsPath, playCount, isFavorite, artworkData, artworkPath
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        path = try c.decode(String.self, forKey: .path)
        title = try c.decode(String.self, forKey: .title)
        artist = try c.decodeIfPresent(String.self, forKey: .artist) ?? ""
        album = try c.decodeIfPresent(String.self, forKey: .album) ?? ""
        duration = try c.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? 0
        lyricsPath = try c.decodeIfPresent(String.self, forKey: .lyricsPath)
        lyricsOffset = try c.decodeIfPresent(Double.self, forKey: .lyricsOffset) ?? 0
        lyricsDisabled = try c.decodeIfPresent(Bool.self, forKey: .lyricsDisabled) ?? false
        playCount = try c.decodeIfPresent(Int.self, forKey: .playCount) ?? 0
        isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        storedArtwork = try c.decodeIfPresent(Data.self, forKey: .artworkData)
        artworkPath = try c.decodeIfPresent(String.self, forKey: .artworkPath)
        artist = MetadataText.repaired(artist)
        album = MetadataText.repaired(album)
        title = MetadataText.title(title, path: path, artist: artist)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(path, forKey: .path)
        try c.encode(title, forKey: .title); try c.encode(artist, forKey: .artist); try c.encode(album, forKey: .album)
        try c.encode(duration, forKey: .duration); try c.encode(lyricsOffset, forKey: .lyricsOffset)
        try c.encode(lyricsDisabled, forKey: .lyricsDisabled); try c.encodeIfPresent(lyricsPath, forKey: .lyricsPath)
        try c.encode(playCount, forKey: .playCount); try c.encode(isFavorite, forKey: .isFavorite)
        try c.encodeIfPresent(storedArtwork, forKey: .artworkData); try c.encodeIfPresent(artworkPath, forKey: .artworkPath)
    }

    /// 从音频/视频文件读取元数据，构建 Song
    static func load(at url: URL) -> Song? {
        if videoExtensions.contains(url.pathExtension.lowercased()) {
            return loadVideo(at: url)
        }
        guard let preview = try? AVAudioPlayer(contentsOf: url) else { return nil }
        let duration = preview.duration

        let asset = AVURLAsset(url: url)
        let metadata = asset.commonMetadata
        func field(_ key: AVMetadataKey) -> String {
            metadata.first { $0.commonKey == key }?.stringValue ?? ""
        }
        let artwork = metadata
            .first { $0.commonKey == .commonKeyArtwork }?
            .dataValue

        let fallbackTitle = url.deletingPathExtension().lastPathComponent
        let title = field(.commonKeyTitle)
        var song = Song(
            path: url.path,
            title: title.isEmpty ? fallbackTitle : title,
            artist: field(.commonKeyArtist),
            album: albumField(from: metadata),
            duration: duration,
            artworkData: artwork
        )
        song.artist = MetadataText.repaired(song.artist)
        song.album = MetadataText.repaired(song.album)
        song.title = MetadataText.title(song.title, path: song.path, artist: song.artist)
        // 重新导入同一路径的文件时，保留播放次数/收藏/歌词绑定
        if let existing = SongLibraryCache.existing?[url.path] {
            song.playCount = existing.playCount
            song.isFavorite = existing.isFavorite
            song.lyricsPath = existing.lyricsPath
            song.lyricsDisabled = existing.lyricsDisabled
        }
        return song
    }

    /// 视频文件：用 AVURLAsset 读取时长与元数据
    private static func loadVideo(at url: URL) -> Song? {
        let asset = AVURLAsset(url: url)
        let duration = asset.duration.seconds
        guard duration.isFinite, duration > 0 else { return nil }

        let metadata = asset.commonMetadata
        func field(_ key: AVMetadataKey) -> String {
            metadata.first { $0.commonKey == key }?.stringValue ?? ""
        }
        let fallbackTitle = url.deletingPathExtension().lastPathComponent
        let title = field(.commonKeyTitle)
        var song = Song(
            path: url.path,
            title: title.isEmpty ? fallbackTitle : title,
            artist: field(.commonKeyArtist),
            album: albumField(from: metadata),
            duration: duration
        )
        song.artist = MetadataText.repaired(song.artist)
        song.album = MetadataText.repaired(song.album)
        song.title = MetadataText.title(song.title, path: song.path, artist: song.artist)
        if let existing = SongLibraryCache.existing?[url.path] {
            song.playCount = existing.playCount
            song.isFavorite = existing.isFavorite
            song.lyricsPath = existing.lyricsPath
            song.lyricsDisabled = existing.lyricsDisabled
        }
        return song
    }

    private static func albumField(from metadata: [AVMetadataItem]) -> String {
        for item in metadata {
            if let k = item.key as? String,
               k == "TALB" || k == "album" || k == "©alb",
               let v = item.stringValue, !v.isEmpty {
                return v
            }
        }
        return ""
    }
}

/// 重新导入同名文件时用于保留播放次数/收藏等统计
enum SongLibraryCache {
    static var existing: [String: Song]?
}

// MARK: - 文本读取（兼容 UTF-8 与 GBK 编码的 LRC）

enum TextFileReader {
    static func read(_ url: URL) -> String? {
        if let s = try? String(contentsOf: url, encoding: .utf8) { return s }
        guard let data = try? Data(contentsOf: url) else { return nil }
        let gbk = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        return String(data: data, encoding: gbk)
    }
}
