import Foundation

/// A one-time snapshot, never a link or a continuing synchronization.
enum BetaDataBootstrap {
    static let marker = "beta-production-snapshot-v1.json"
    static func copyOnce(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: destination.appendingPathComponent(marker).path),
              fm.fileExists(atPath: source.appendingPathComponent("library.json").path) else { return }
        let parent = destination.deletingLastPathComponent()
        let stage = parent.appendingPathComponent(".MyPlayerBeta-snapshot-" + UUID().uuidString)
        defer { try? fm.removeItem(at: stage) }
        // Reject links so no beta-owned file can alias production data.
        func copy(_ input: URL, _ output: URL) throws {
            let values = try input.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey])
            guard values.isSymbolicLink != true else { throw CocoaError(.fileReadUnsupportedScheme) }
            if values.isDirectory == true {
                try fm.createDirectory(at: output, withIntermediateDirectories: true)
                for child in try fm.contentsOfDirectory(at: input, includingPropertiesForKeys: nil) {
                    try copy(child, output.appendingPathComponent(child.lastPathComponent))
                }
            } else if values.isRegularFile == true {
                try fm.copyItem(at: input, to: output)
            }
        }
        try copy(source, stage)
        func relocate(_ value: Any) -> Any {
            if let string = value as? String {
                for (old, new) in [(source.path + "/", destination.path + "/"), (source.absoluteString, destination.absoluteString)] {
                    if string.hasPrefix(old) { return new + string.dropFirst(old.count) }
                }
                return string
            }
            if let array = value as? [Any] { return array.map(relocate) }
            if let dict = value as? [String: Any] { return dict.mapValues(relocate) }
            return value
        }
        if let files = fm.enumerator(at: stage, includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let file as URL in files {
                guard ["json", "plist"].contains(file.pathExtension),
                      try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
                let bytes = try Data(contentsOf: file)
                if file.pathExtension == "json" {
                    let object = try JSONSerialization.jsonObject(with: bytes, options: .fragmentsAllowed)
                    try JSONSerialization.data(withJSONObject: relocate(object), options: [.sortedKeys, .fragmentsAllowed]).write(to: file, options: .atomic)
                } else {
                    let object = try PropertyListSerialization.propertyList(from: bytes, format: nil)
                    try PropertyListSerialization.data(fromPropertyList: relocate(object), format: .xml, options: 0).write(to: file, options: .atomic)
                }
            }
        }
        try Data("{\"schema\":1,\"source\":\"MyPlayer\",\"mode\":\"independent-copy\"}".utf8)
            .write(to: stage.appendingPathComponent(marker), options: .atomic)
        let backup = parent.appendingPathComponent("MyPlayer Beta Backup-" + UUID().uuidString)
        let existed = fm.fileExists(atPath: destination.path)
        if existed { try fm.moveItem(at: destination, to: backup) }
        do { try fm.moveItem(at: stage, to: destination) }
        catch {
            if existed { try? fm.moveItem(at: backup, to: destination) }
            throw error
        }
    }
}
