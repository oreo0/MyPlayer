import Foundation
struct Song {
    var title: String
    var artist: String
    var url: URL
}
let one = Song(title: "Song A", artist: "Artist A", url: URL(fileURLWithPath: "/audio/a.mp3"))
let two = Song(title: "Song A", artist: "Artist B", url: URL(fileURLWithPath: "/audio/b.mp3"))
func match(_ name: String, _ content: String, _ songs: [Song] = [one, two]) -> Song? {
    LyricsMatcher.match(url: URL(fileURLWithPath: name), content: content, songs: songs)
}
precondition(match("a.lrc", "")?.artist == "Artist A")
precondition(match("unknown.lrc", "[ti:Song A]\n[ar:Artist B]")?.artist == "Artist B")
precondition(match("Song A.lrc", "") == nil)
precondition(match("Artist A - Song A.lrc", "")?.artist == "Artist A")
precondition(match("unrelated.lrc", "[ti:Different]") == nil)
precondition(match("a.lrc", "[ti:Song A]\n[ar:Artist B]")?.artist == "Artist B")
print("PASS: filenames, artist-title names, LRC tags, ambiguity and conflicting filename")
