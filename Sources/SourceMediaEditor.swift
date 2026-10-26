import Foundation
import AVFoundation
import ImageIO
import CryptoKit
import UniformTypeIdentifiers
import Darwin

/// All staging and backups are local. Only a successful atomic replacement is exposed to the library.
enum SourceMediaEditor {
    struct Result: Sendable { let url: URL; let backup: URL }
    private struct Fingerprint: Equatable {
        let size: UInt64; let modified: Date; let inode: UInt64
        init(_ url: URL) throws {
            let a = try FileManager.default.attributesOfItem(atPath: url.path)
            guard a[.type] as? FileAttributeType == .typeRegular else { throw SourceMediaError.invalid("只能修改普通媒体文件。") }
            size = (a[.size] as? NSNumber)?.uint64Value ?? 0
            modified = a[.modificationDate] as? Date ?? .distantPast
            inode = (a[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
        }
    }
    static let supportedExtensions: Set<String> = ["mp3", "flac", "wav", "wave", "aif", "aiff", "aifc", "m4a", "m4b", "mp4", "m4v", "mov"]
    static func filename(title: String, artist: String, extension ext: String) throws -> String {
        func safe(_ text: String) -> String {
            text.components(separatedBy: CharacterSet(charactersIn: "/:\\").union(.controlCharacters)).joined(separator: "_").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let title = safe(title), artist = safe(artist)
        guard !title.isEmpty, title != ".", title != ".." else { throw SourceMediaError.invalid("请填写有效的文件标题。") }
        let stem = artist.isEmpty ? title : "\(title) - \(artist)"
        let result = ext.isEmpty ? stem : stem + "." + ext
        guard result.utf8.count <= 255 else { throw SourceMediaError.invalid("标题与艺人名过长，无法用作文件名。") }
        return result
    }
    static func normalizedArtwork(_ data: Data?) throws -> Data? {
        guard let data else { return nil }
        guard data.count <= 32 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw SourceMediaError.invalid("封面不是有效图片，或超过 32 MB。") }
        let type = CGImageSourceGetType(source) as String?
        if type == UTType.jpeg.identifier || type == UTType.png.identifier { return data }
        let result = NSMutableData()
        guard let target = CGImageDestinationCreateWithData(result, UTType.png.identifier as CFString, 1, nil) else { throw SourceMediaError.invalid("无法转换封面图片。") }
        CGImageDestinationAddImage(target, image, nil)
        guard CGImageDestinationFinalize(target) else { throw SourceMediaError.invalid("无法转换封面图片。") }
        return result as Data
    }
    static func write(_ source: URL, metadata: SourceMediaMetadata, backupRoot: URL) async throws -> Result {
        try await Task.detached(priority: .userInitiated) { try await perform(source, metadata: metadata, backupRoot: backupRoot) }.value
    }
    private static func perform(_ source: URL, metadata: SourceMediaMetadata, backupRoot: URL) async throws -> Result {
        let fm = FileManager.default, ext = source.pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else { throw SourceMediaError.unsupported(ext) }
        let scoped = source.startAccessingSecurityScopedResource(); defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let before = try Fingerprint(source)
        let parent = source.deletingLastPathComponent()
        guard fm.isWritableFile(atPath: source.path), fm.isWritableFile(atPath: parent.path) else { throw SourceMediaError.invalid("源文件或所在文件夹不可写，请先在访达中检查权限。") }
        let destination = parent.appendingPathComponent(try filename(title: metadata.title, artist: metadata.artist, extension: source.pathExtension))
        // Resource identifiers also handle case-insensitive volumes and case-only renames.
        let sameFile: Bool
        if fm.fileExists(atPath: destination.path) { sameFile = try Fingerprint(destination).inode == before.inode }
        else { sameFile = false }
        guard !fm.fileExists(atPath: destination.path) || sameFile else { throw SourceMediaError.collision }
        let artwork = try normalizedArtwork(metadata.artwork)
        let tags = SourceMediaMetadata(title: metadata.title, artist: metadata.artist, album: metadata.album, artwork: artwork)
        let stage = parent.appendingPathComponent(".MyPlayer-edit-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: stage, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: stage) }
        let output = stage.appendingPathComponent("edited." + source.pathExtension)
        switch ext {
        case "mp3": try SourceTagCodec.mp3(source, output, tags)
        case "flac": try SourceTagCodec.flac(source, output, tags)
        case "wav", "wave": try SourceTagCodec.riff(source, output, tags, aiff: false)
        case "aif", "aiff", "aifc": try SourceTagCodec.riff(source, output, tags, aiff: true)
        default: try await exportContainer(source, output, tags)
        }
        if ext == "flac" {
            guard let saved = AudioFileMetadata.read(output), saved.title == tags.title, saved.artist == tags.artist,
                  saved.album == tags.album, saved.artwork == tags.artwork else {
                throw SourceMediaError.invalid("系统未能完整读回写入的信息与封面，源文件未修改。")
            }
        } else {
            try await verifyMetadata(output, tags)
        }
        guard copyfile(source.path, output.path, nil, copyfile_flags_t(COPYFILE_XATTR | COPYFILE_ACL)) == 0 else {
            throw SourceMediaError.invalid("无法保留源文件的访达属性与访问权限，源文件未修改。")
        }
        let attributes = try fm.attributesOfItem(atPath: source.path)
        if let created = attributes[.creationDate] { try fm.setAttributes([.creationDate: created], ofItemAtPath: output.path) }
        if let mode = attributes[.posixPermissions] { try fm.setAttributes([.posixPermissions: mode], ofItemAtPath: output.path) }
        try Task.checkCancellation()
        guard try Fingerprint(source) == before else { throw SourceMediaError.changed }
        let backupFolder = backupRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: backupFolder, withIntermediateDirectories: true)
        let backup = backupFolder.appendingPathComponent(source.lastPathComponent)
        try fm.copyItem(at: source, to: backup)
        guard try digest(source) == digest(backup), try Fingerprint(source) == before else { throw SourceMediaError.changed }
        let manifest = ["originalPath": source.path, "updatedPath": destination.path, "createdAt": ISO8601DateFormatter().string(from: Date())]
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]).write(to: backupFolder.appendingPathComponent("restore.json"), options: .atomic)
        // moveItem never replaces an unrelated destination. Keep the original until commit succeeds.
        let holding = stage.appendingPathComponent("original." + source.pathExtension)
        try fm.moveItem(at: source, to: holding)
        do {
            try fm.moveItem(at: output, to: destination)
        } catch {
            // The old path was vacant a moment ago; if another process claims it, preserve original in backup.
            do { try fm.moveItem(at: holding, to: source) }
            catch { throw SourceMediaError.invalid("保存失败，原始文件已完整保存在：\(backup.path)") }
            throw error
        }
        return Result(url: destination, backup: backup)
    }
    static func digest(_ url: URL) throws -> Data {
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }; var hash = SHA256()
        while let part = try file.read(upToCount: 1_048_576), !part.isEmpty { hash.update(data: part) }
        return Data(hash.finalize())
    }
    private static func exportContainer(_ source: URL, _ output: URL, _ tags: SourceMediaMetadata) async throws {
        let asset = AVURLAsset(url: source)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else { throw SourceMediaError.unsupported(source.pathExtension) }
        let mov = source.pathExtension.lowercased() == "mov"
        let type: AVFileType = mov ? .mov : (["m4a", "m4b"].contains(source.pathExtension.lowercased()) ? .m4a : .mp4)
        guard export.supportedFileTypes.contains(type) else { throw SourceMediaError.unsupported(source.pathExtension) }
        let targetIDs: Set<AVMetadataIdentifier> = [.commonIdentifierTitle, .commonIdentifierArtist, .commonIdentifierAlbumName, .commonIdentifierArtwork, .iTunesMetadataSongName, .iTunesMetadataArtist, .iTunesMetadataAlbum, .iTunesMetadataCoverArt, .quickTimeMetadataTitle, .quickTimeMetadataArtist, .quickTimeMetadataAlbum, .quickTimeMetadataArtwork]
        var kept: [AVMetadataItem] = []
        for format in try await asset.load(.availableMetadataFormats) {
            for item in try await asset.loadMetadata(for: format) {
                if let identifier = item.identifier, targetIDs.contains(identifier) { continue }
                if let key = item.commonKey, [.commonKeyTitle, .commonKeyArtist, .commonKeyAlbumName, .commonKeyArtwork].contains(key) { continue }
                kept.append(item)
            }
        }
        let ids: [AVMetadataIdentifier] = mov ? [.quickTimeMetadataTitle, .quickTimeMetadataArtist, .quickTimeMetadataAlbum] : [.iTunesMetadataSongName, .iTunesMetadataArtist, .iTunesMetadataAlbum]
        for (id, text) in zip(ids, [tags.title, tags.artist, tags.album]) {
            let item = AVMutableMetadataItem(); item.identifier = id; item.value = text as NSString; item.dataType = kCMMetadataBaseDataType_UTF8 as String; kept.append(item)
        }
        if let cover = tags.artwork {
            let item = AVMutableMetadataItem(); item.identifier = mov ? .quickTimeMetadataArtwork : .iTunesMetadataCoverArt; item.value = cover as NSData
            item.dataType = (tags.mime == "image/jpeg" ? kCMMetadataBaseDataType_JPEG : kCMMetadataBaseDataType_PNG) as String; kept.append(item)
        }
        export.metadata = kept
        try await export.export(to: output, as: type)
        let result = AVURLAsset(url: output)
        let originalDuration = try await asset.load(.duration).seconds, newDuration = try await result.load(.duration).seconds
        guard abs(originalDuration - newDuration) < 0.05, try await asset.load(.tracks).count == result.load(.tracks).count else { throw SourceMediaError.invalid("媒体轨道校验失败，源文件未修改。") }
    }
    private static func verifyMetadata(_ url: URL, _ tags: SourceMediaMetadata) async throws {
        let common = try await AVURLAsset(url: url).load(.commonMetadata)
        for (key, expected) in zip([AVMetadataKey.commonKeyTitle, .commonKeyArtist, .commonKeyAlbumName], [tags.title, tags.artist, tags.album]) {
            var values: [String] = []
            for item in common where item.commonKey == key { if let value = try await item.load(.stringValue) { values.append(value) } }
            guard expected.isEmpty ? values.allSatisfy(\.isEmpty) : values.contains(expected) else { throw SourceMediaError.invalid("此文件未能完整保存信息，源文件未修改。") }
        }
        var covers: [Data] = []
        for item in common where item.commonKey == .commonKeyArtwork { if let data = try await item.load(.dataValue) { covers.append(data) } }
        if let cover = tags.artwork {
            guard covers.contains(cover) else { throw SourceMediaError.invalid("此容器无法完整保存封面，源文件未修改。") }
        } else if !covers.isEmpty { throw SourceMediaError.invalid("此容器未能移除封面，源文件未修改。") }
    }

}
