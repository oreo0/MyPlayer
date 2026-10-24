import Foundation

let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: folder) }
let url = folder.appendingPathComponent("record.json")
func contents() throws -> String { String(decoding: try Data(contentsOf: url), as: UTF8.self) }
func expect(_ text: String) throws { let value = try contents(); precondition(value == text) }
try Data("initial".utf8).write(to: url, options: .atomic)
UserDataFiles.accept(url)
UserDataFiles.write(Data("owned update".utf8), to: url)
UserDataFiles.flush()
try expect("owned update")
try Data("external replacement".utf8).write(to: url, options: .atomic)
UserDataFiles.write(Data("stale memory".utf8), to: url)
UserDataFiles.flush()
try expect("external replacement")
UserDataFiles.accept(url)
UserDataFiles.write(Data("edited imported data".utf8), to: url)
UserDataFiles.flush()
try expect("edited imported data")

struct SlowSnapshot: Encodable, @unchecked Sendable {
    let entered: DispatchSemaphore
    let release: DispatchSemaphore
    func encode(to encoder: Encoder) throws {
        entered.signal(); release.wait()
        var container = encoder.singleValueContainer(); try container.encode("stale queued snapshot")
    }
}
let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
UserDataFiles.save(SlowSnapshot(entered: entered, release: release), to: url)
precondition(entered.wait(timeout: .now() + 5) == .success)
try Data("imported while encoding".utf8).write(to: url, options: .atomic)
UserDataFiles.accept(url)
release.signal()
UserDataFiles.flush()
try expect("imported while encoding")
let before = UserDataFiles.revision(url)
try Data("changed during validation".utf8).write(to: url, options: .atomic)
precondition(!UserDataFiles.accept(url, expectedRevision: before))
UserDataFiles.write(Data("must not overwrite".utf8), to: url)
UserDataFiles.flush()
try expect("changed during validation")

var palette = VideoMoreState()
palette.hoverMore(); precondition(palette.isExpanded)
palette.leavePanel(popupOpen: false); precondition(!palette.isExpanded)
palette.hoverMore(); palette.clickMore(); palette.leavePanel(popupOpen: false)
precondition(palette.isExpanded && palette.source == .pinned)
palette.hidePanel(); precondition(palette.isExpanded)
palette.clickMore(); precondition(!palette.isExpanded)
palette.clickMore(); palette.popupClosed(pointerInside: false); precondition(palette.isExpanded)
palette.clickMore(); palette.hoverMore(); palette.leavePanel(popupOpen: true)
precondition(palette.isExpanded)
palette.popupClosed(pointerInside: false); precondition(!palette.isExpanded)
print("PASS: revision protection, queued import race, read-validation race, hover/click palette state")
