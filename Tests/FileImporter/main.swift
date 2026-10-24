import Foundation
struct Song { static let videoExtensions: Set<String> = ["mp4"] }
let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: root.appendingPathComponent("nested"), withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }
let song = root.appendingPathComponent("nested/no-lyrics.mp3")
try Data([0]).write(to: song)
let expanded = FileImporter.expandDroppedURLs([root, song])
precondition(expanded.count == 1 && expanded[0].resolvingSymlinksInPath() == song.resolvingSymlinksInPath())

print("PASS: nested folder without lyrics expands media and removes duplicate paths")
