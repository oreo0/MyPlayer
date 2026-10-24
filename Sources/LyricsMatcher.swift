import Foundation

/// Exact normalized matches only; ambiguity is left for the user to resolve.
enum LyricsMatcher {
    static func match(url: URL, content: String, songs: [Song]) -> Song? {
        func tag(_ key: String) -> String {
            guard let regex = try? NSRegularExpression(pattern: "\\[" + key + ":([^\\]]+)\\]", options: .caseInsensitive),
                  let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
                  let range = Range(match.range(at: 1), in: content) else { return "" }
            return normalize(String(content[range]))
        }
        let title = tag("ti"), artist = tag("ar")
        let base = normalize(url.deletingPathExtension().lastPathComponent)
        let ranked = songs.compactMap { song -> (Song, Int)? in
            let songTitle = normalize(song.title), songArtist = normalize(song.artist)
            if !artist.isEmpty && !songArtist.isEmpty && artist != songArtist { return nil }
            var score = 0
            if base == normalize(song.url.deletingPathExtension().lastPathComponent) { score = 100 }
            if !songTitle.isEmpty && (base == songTitle || (!songArtist.isEmpty && (base == songArtist + songTitle || base == songTitle + songArtist))) { score = max(score, 80) }
            if !title.isEmpty && title == songTitle { score += 180 }
            if score > 0 && !artist.isEmpty && artist == songArtist { score += 30 }
            return score > 0 ? (song, score) : nil
        }.sorted { $0.1 > $1.1 }
        guard let first = ranked.first, ranked.count == 1 || first.1 > ranked[1].1 else { return nil }
        return first.0
    }
    static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }
}
