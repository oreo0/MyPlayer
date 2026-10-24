import Foundation

enum CoverGrouping: String, CaseIterable, Identifiable {
    case album, artist, folder
    var id: String { rawValue }
    var title: String { switch self { case .album: "专辑"; case .artist: "艺人"; case .folder: "源文件夹" } }
    var icon: String { switch self { case .album: "square.stack"; case .artist: "person"; case .folder: "folder" } }
    func groups(_ songs: [Song]) -> [MediaCoverGroup] {
        var result: [MediaCoverGroup] = [], positions: [String: Int] = [:]
        for song in songs {
            let value: String
            switch self {
            case .album: value = song.album.trimmingCharacters(in: .whitespacesAndNewlines)
            case .artist: value = song.artist.trimmingCharacters(in: .whitespacesAndNewlines)
            case .folder: value = URL(fileURLWithPath: song.path).deletingLastPathComponent().standardizedFileURL.path
            }
            let key = rawValue + ":" + value.precomposedStringWithCanonicalMapping
            if let index = positions[key] { result[index].songs.append(song) }
            else {
                positions[key] = result.count
                let title = self == .folder ? URL(fileURLWithPath: value).lastPathComponent : (value.isEmpty ? (self == .album ? "未知专辑" : "未知艺人") : value)
                result.append(MediaCoverGroup(id: key, title: title, kind: self, songs: [song]))
            }
        }
        return result
    }
}
struct MediaCoverGroup: Identifiable {
    let id: String
    let title: String
    let kind: CoverGrouping
    var songs: [Song]
    var representative: Song? { songs.first(where: \.hasArtwork) ?? songs.first }
}
