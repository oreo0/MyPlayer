import Foundation
import Combine
let time = CurrentValueSubject<TimeInterval, Never>(2.9)
let lines = LRCParser.parse("[00:01]first\n[00:03]second")
var delayed: Int??, advanced: Int??
let a = LyricProgress.indices(times: time, lyrics: lines, offset: 0.2).sink { delayed = .some($0) }
let b = LyricProgress.indices(times: time, lyrics: lines, offset: -0.2).sink { advanced = .some($0) }
precondition(delayed! == 0 && advanced! == 1)
time.send(3.2)
precondition(delayed! == 1)
var song = Song(path: "/tmp/music.m4a", title: "Test", artist: "Artist", album: "Album", duration: 90)
song.lyricsOffset = -0.2
let encoded = try JSONEncoder().encode(song)
let restored = try JSONDecoder().decode(Song.self, from: encoded)
precondition(restored.lyricsOffset == -0.2)
var legacy = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
legacy.removeValue(forKey: "lyricsOffset")
let legacyData = try JSONSerialization.data(withJSONObject: legacy)
let migrated = try JSONDecoder().decode(Song.self, from: legacyData)
precondition(migrated.lyricsOffset == 0)
print("PASS: 0.2s advance/delay, exact lyric boundary, persisted per-track offset and legacy defaults")
