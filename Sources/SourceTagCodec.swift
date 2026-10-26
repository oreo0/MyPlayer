import Foundation
import ImageIO

struct SourceMediaMetadata: Sendable {
    let title: String
    let artist: String
    let album: String
    let artwork: Data?
    var mime: String { artwork?.starts(with: [0xff, 0xd8]) == true ? "image/jpeg" : "image/png" }
}

enum SourceMediaError: LocalizedError {
    case invalid(String), unsupported(String), collision, changed
    var errorDescription: String? {
        switch self {
        case .invalid(let text): text
        case .unsupported(let ext): "当前暂不支持将完整信息与封面写回 \(ext.uppercased()) 源文件；原文件和资料库未修改。"
        case .collision: "目标文件名已存在，请修改标题或艺人名。不会覆盖已有文件。"
        case .changed: "源文件在保存期间发生变化，已停止写入，请重新打开编辑。"
        }
    }
}

enum SourceTagCodec {
    struct Frame { var id: String; var flags: UInt16; var body: Data }
    static func number(_ data: Data, _ offset: Int, _ count: Int, little: Bool = false) throws -> UInt64 {
        guard offset >= 0, count >= 0, offset <= data.count, count <= data.count - offset else { throw SourceMediaError.invalid("源文件元数据不完整。") }
        let bytes = Array(data[offset..<offset + count])
        return (little ? Array(bytes.reversed()) : bytes).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }
    static func bytes(_ number: UInt64, count: Int = 4, little: Bool = false) -> Data {
        let values = (0..<count).map { UInt8(truncatingIfNeeded: number >> ($0 * 8)) }
        return Data(little ? values : Array(values.reversed()))
    }
    static func syncSize(_ value: Int) -> Data { Data([UInt8((value >> 21) & 127), UInt8((value >> 14) & 127), UInt8((value >> 7) & 127), UInt8(value & 127)]) }
    static func syncNumber(_ data: Data, _ offset: Int) throws -> Int {
        guard offset >= 0, offset + 4 <= data.count else { throw SourceMediaError.invalid("ID3 长度无效。") }
        return try data[offset..<offset + 4].reduce(0) { value, byte in
            guard byte < 128 else { throw SourceMediaError.invalid("ID3 长度无效。") }; return (value << 7) | Int(byte)
        }
    }
    static func read(_ file: FileHandle, count: Int) throws -> Data {
        guard count >= 0, count <= 64 * 1024 * 1024 else { throw SourceMediaError.invalid("元数据块过大，未修改源文件。") }
        var result = Data()
        while result.count < count {
            guard let next = try file.read(upToCount: count - result.count), !next.isEmpty else { throw SourceMediaError.invalid("源文件数据不完整。") }
            result.append(next)
        }
        return result
    }
    static func copy(_ input: FileHandle, to output: FileHandle, count: UInt64) throws {
        var remaining = count
        while remaining > 0 {
            try Task.checkCancellation()
            let chunk = try read(input, count: Int(min(1_048_576, remaining)))
            try output.write(contentsOf: chunk); remaining -= UInt64(chunk.count)
        }
    }
    static func deunsync(_ data: Data) -> Data {
        let input = Array(data); var result = Data(); var i = 0
        while i < input.count {
            result.append(input[i]); if input[i] == 255 && i + 1 < input.count && input[i + 1] == 0 { i += 1 }; i += 1
        }
        return result
    }
    static func frames(_ original: Data) throws -> (version: Int, flags: UInt8, frames: [Frame]) {
        guard original.count >= 10, original.prefix(3) == Data("ID3".utf8), [2, 3, 4].contains(original[3]) else { throw SourceMediaError.invalid("不支持的 ID3 标签版本。") }
        let version = Int(original[3]), flags = original[5]
        guard !(version == 2 && flags & 0x40 != 0) else { throw SourceMediaError.invalid("暂不支持压缩的 ID3v2.2 标签。") }
        var body = Data(original.dropFirst(10))
        if version < 4 && flags & 0x80 != 0 { body = deunsync(body) }
        var offset = 0
        if version >= 3 && flags & 0x40 != 0 {
            offset = version == 3 ? Int(try number(body, 0, 4)) + 4 : try syncNumber(body, 0)
            guard offset >= 6, offset <= body.count else { throw SourceMediaError.invalid("ID3 扩展头损坏。") }
        }
        var result: [Frame] = []
        let header = version == 2 ? 6 : 10
        while offset + header <= body.count && body[offset] != 0 {
            let width = version == 2 ? 3 : 4
            let nameData = body[offset..<offset + width]
            guard nameData.allSatisfy({ (65...90).contains($0) || (48...57).contains($0) }), let id = String(data: nameData, encoding: .ascii) else { throw SourceMediaError.invalid("ID3 标签帧损坏。") }
            let size = version == 4 ? try syncNumber(body, offset + 4) : Int(try number(body, offset + width, version == 2 ? 3 : 4))
            guard size > 0, size <= body.count - offset - header else { throw SourceMediaError.invalid("ID3 标签帧长度无效。") }
            var frameFlags = version == 2 ? UInt16(0) : UInt16(try number(body, offset + 8, 2))
            var payload = Data(body[offset + header..<offset + header + size])
            if version == 4 && (flags & 0x80 != 0 || frameFlags & 2 != 0) { payload = deunsync(payload); frameFlags &= ~2 }
            let discard = version == 3 ? frameFlags & 0x8000 != 0 : (version == 4 && frameFlags & 0x4000 != 0)
            if !discard { result.append(Frame(id: id, flags: frameFlags, body: payload)) }
            offset += header + size
        }
        return (version, flags & 0x20, result)
    }
    static func id3(_ metadata: SourceMediaMetadata, original: Data? = nil) throws -> Data {
        let saved = try original.map(frames) ?? (version: 3, flags: UInt8(0), frames: [Frame]())
        let targets: Set<String> = ["TIT2", "TPE1", "TALB", "APIC", "TT2", "TP1", "TAL", "PIC"]
        var result = saved.frames.filter { !targets.contains($0.id) }
        for (id, text) in zip(saved.version == 2 ? ["TT2", "TP1", "TAL"] : ["TIT2", "TPE1", "TALB"], [metadata.title, metadata.artist, metadata.album]) {
            let body: Data
            if saved.version == 4 { body = Data([3]) + Data(text.utf8) }
            else { body = Data([1, 255, 254]) + (text.data(using: .utf16LittleEndian) ?? Data()) }
            result.append(Frame(id: id, flags: 0, body: body))
        }
        if let artwork = metadata.artwork {
            let prefix = saved.version == 2 ? Data([0]) + Data((metadata.mime == "image/jpeg" ? "JPG" : "PNG").utf8) : Data([0]) + Data(metadata.mime.utf8) + Data([0])
            result.append(Frame(id: saved.version == 2 ? "PIC" : "APIC", flags: 0, body: prefix + Data([3, 0]) + artwork))
        }
        var payload = Data()
        for frame in result {
            payload.append(Data(frame.id.utf8))
            if saved.version == 2 { guard frame.body.count < 1 << 24 else { throw SourceMediaError.invalid("封面超出 ID3v2.2 容量。") }; payload.append(bytes(UInt64(frame.body.count), count: 3)) }
            else { payload.append(saved.version == 4 ? syncSize(frame.body.count) : bytes(UInt64(frame.body.count))); payload.append(bytes(UInt64(frame.flags), count: 2)) }
            payload.append(frame.body)
        }
        guard payload.count < 1 << 28 else { throw SourceMediaError.invalid("ID3 标签过大。") }
        return Data("ID3".utf8) + Data([UInt8(saved.version), 0, saved.flags]) + syncSize(payload.count) + payload
    }
    static func mp3(_ source: URL, _ output: URL, _ metadata: SourceMediaMetadata) throws {
        let input = try FileHandle(forReadingFrom: source); defer { try? input.close() }
        let total = try input.seekToEnd(); try input.seek(toOffset: 0)
        guard total >= 10 else { throw SourceMediaError.invalid("MP3 源文件不完整。") }
        let header = try read(input, count: 10); var start: UInt64 = 0; var original: Data?
        if header.prefix(3) == Data("ID3".utf8) {
            let length = try syncNumber(header, 6)
            guard UInt64(length) <= total - 10 else { throw SourceMediaError.invalid("ID3 标签超出文件长度。") }
            original = header + (try read(input, count: length)); start = UInt64(length + 10)
            if header[3] == 4 && header[5] & 0x10 != 0 { start += 10 }
        }
        var end = total; var legacy: Data?
        if total >= 128 { try input.seek(toOffset: total - 128); if try read(input, count: 3) == Data("TAG".utf8) {
                try input.seek(toOffset: total - 128); var tag = try read(input, count: 128)
                for (offset, value) in zip([3, 33, 63], [metadata.title, metadata.artist, metadata.album]) {
                    let ascii = Data(value.unicodeScalars.map { $0.value < 128 ? UInt8($0.value) : 63 }.prefix(30))
                    tag.replaceSubrange(offset..<offset + 30, with: ascii + Data(count: 30 - ascii.count))
                }
                legacy = tag; end -= 128
            } }
        guard start < end else { throw SourceMediaError.invalid("MP3 文件缺少媒体数据。") }
        FileManager.default.createFile(atPath: output.path, contents: nil)
        let destination = try FileHandle(forWritingTo: output); defer { try? destination.close() }
        try destination.write(contentsOf: id3(metadata, original: original)); try input.seek(toOffset: start); try copy(input, to: destination, count: end - start)
        if let legacy { try destination.write(contentsOf: legacy) }
        try destination.synchronize()
    }
    static func flac(_ source: URL, _ output: URL, _ metadata: SourceMediaMetadata) throws {
        let input = try FileHandle(forReadingFrom: source); defer { try? input.close() }
        let total = try input.seekToEnd(); try input.seek(toOffset: 0)
        guard try read(input, count: 4) == Data("fLaC".utf8) else { throw SourceMediaError.invalid("FLAC 文件头无效。") }
        var blocks: [(UInt8, Data)] = []; var last = false; var vendor = Data("MyPlayer".utf8); var comments: [Data] = []
        while !last {
            guard blocks.count < 1024 else { throw SourceMediaError.invalid("FLAC 元数据块过多。") }
            let header = try read(input, count: 4); last = header[0] & 128 != 0; let type = header[0] & 127
            let body = try read(input, count: Int(try number(header, 1, 3)))
            if type == 4 {
                var cursor = 0
                func field() throws -> Data { let length = Int(try number(body, cursor, 4, little: true)); cursor += 4; guard length <= body.count - cursor else { throw SourceMediaError.invalid("FLAC 注释块损坏。") }; defer { cursor += length }; return Data(body[cursor..<cursor + length]) }
                vendor = try field(); let count = Int(try number(body, cursor, 4, little: true)); cursor += 4
                guard count <= body.count / 4 else { throw SourceMediaError.invalid("FLAC 注释数量无效。") }
                for _ in 0..<count { let value = try field(); let key = String(decoding: value.prefix { $0 != 61 }, as: UTF8.self).uppercased(); if !["TITLE", "ARTIST", "ALBUM"].contains(key) { comments.append(value) } }
            } else if type != 6 && type != 1 { blocks.append((type, body)) }
        }
        guard blocks.first?.0 == 0, blocks.first?.1.count == 34 else { throw SourceMediaError.invalid("FLAC STREAMINFO 无效。") }
        for (key, value) in zip(["TITLE", "ARTIST", "ALBUM"], [metadata.title, metadata.artist, metadata.album]) { comments.append(Data("\(key)=\(value)".utf8)) }
        var comment = bytes(UInt64(vendor.count), little: true) + vendor + bytes(UInt64(comments.count), little: true)
        for value in comments { comment += bytes(UInt64(value.count), little: true) + value }
        blocks.append((4, comment))
        if let image = metadata.artwork {
            let props = CGImageSourceCreateWithData(image as CFData, nil).flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }
            let width = (props?[kCGImagePropertyPixelWidth] as? NSNumber)?.uint64Value ?? 0, height = (props?[kCGImagePropertyPixelHeight] as? NSNumber)?.uint64Value ?? 0
            let mime = Data(metadata.mime.utf8)
            let body = bytes(3) + bytes(UInt64(mime.count)) + mime + bytes(0) + bytes(width) + bytes(height) + bytes(32) + bytes(0) + bytes(UInt64(image.count)) + image
            blocks.append((6, body))
        }
        let start = try input.offset(); guard start < total else { throw SourceMediaError.invalid("FLAC 缺少音频数据。") }
        FileManager.default.createFile(atPath: output.path, contents: nil); let destination = try FileHandle(forWritingTo: output); defer { try? destination.close() }
        try destination.write(contentsOf: Data("fLaC".utf8))
        for (index, block) in blocks.enumerated() {
            guard block.1.count < 1 << 24 else { throw SourceMediaError.invalid("FLAC 元数据超过容量。") }
            try destination.write(contentsOf: Data([block.0 | (index == blocks.count - 1 ? 128 : 0)]) + bytes(UInt64(block.1.count), count: 3) + block.1)
        }
        try copy(input, to: destination, count: total - start); try destination.synchronize()
    }
    static func riff(_ source: URL, _ output: URL, _ metadata: SourceMediaMetadata, aiff: Bool) throws {
        let input = try FileHandle(forReadingFrom: source); defer { try? input.close() }; let total = try input.seekToEnd(); try input.seek(toOffset: 0)
        let header = try read(input, count: 12), little = !aiff
        guard header.prefix(4) == Data((aiff ? "FORM" : "RIFF").utf8), (aiff ? ["AIFF", "AIFC"] : ["WAVE"]).contains(String(decoding: header.suffix(4), as: UTF8.self)), UInt64(try number(header, 4, 4, little: little)) + 8 == total else { throw SourceMediaError.invalid("暂不支持此 RIFF/AIFF 布局，源文件未修改。") }
        FileManager.default.createFile(atPath: output.path, contents: header); let destination = try FileHandle(forWritingTo: output); defer { try? destination.close() }; try destination.seek(toOffset: 12)
        var originalID3: Data?
        while try input.offset() < total {
            let chunk = try read(input, count: 8); let id = String(decoding: chunk.prefix(4), as: UTF8.self), size = try number(chunk, 4, 4, little: little); let offset = try input.offset()
            guard size + (size & 1) <= total - offset else { throw SourceMediaError.invalid("媒体数据块长度无效。") }
            if ["ID3 ", "id3 "].contains(id) {
                guard originalID3 == nil else { throw SourceMediaError.invalid("文件含有多个 ID3 块，未修改源文件。") }
                originalID3 = try read(input, count: Int(size)); if size & 1 == 1 { _ = try read(input, count: 1) }; continue
            }
            if aiff && ["NAME", "AUTH"].contains(id) { try input.seek(toOffset: offset + size + (size & 1)); continue }
            if !aiff && id == "LIST" && size >= 4 {
                let body = try read(input, count: Int(size)); if size & 1 == 1 { _ = try read(input, count: 1) }
                if body.prefix(4) == Data("INFO".utf8) {
                    var preserved = Data("INFO".utf8); var cursor = 4
                    while cursor + 8 <= body.count {
                        let length = Int(try number(body, cursor + 4, 4, little: true)), key = String(decoding: body[cursor..<cursor + 4], as: UTF8.self)
                        let end = cursor + 8 + length + (length & 1); guard end <= body.count else { throw SourceMediaError.invalid("WAV INFO 元数据损坏。") }
                        if !["INAM", "IART", "IPRD"].contains(key) { preserved.append(body[cursor..<end]) }; cursor = end
                    }
                    if preserved.count > 4 { try chunkWrite("LIST", preserved, destination, little: true) }
                } else { try chunkWrite("LIST", body, destination, little: true) }
                continue
            }
            try destination.write(contentsOf: chunk); try copy(input, to: destination, count: size + (size & 1))
        }
        if aiff {
            try chunkWrite("NAME", Data(metadata.title.utf8), destination, little: false)
            try chunkWrite("AUTH", Data(metadata.artist.utf8), destination, little: false)
        } else {
            var info = Data("INFO".utf8)
            for (key, value) in zip(["INAM", "IART", "IPRD"], [metadata.title, metadata.artist, metadata.album]) {
                let data = Data(value.utf8) + Data([0]); info += Data(key.utf8) + bytes(UInt64(data.count), little: true) + data; if data.count & 1 == 1 { info.append(0) }
            }
            try chunkWrite("LIST", info, destination, little: true)
        }
        try chunkWrite("ID3 ", id3(metadata, original: originalID3), destination, little: little)
        let end = try destination.offset(); guard end - 8 <= UInt32.max else { throw SourceMediaError.invalid("文件超出此容器的长度限制。") }
        try destination.seek(toOffset: 4); try destination.write(contentsOf: bytes(end - 8, little: little)); try destination.synchronize()
    }
    private static func chunkWrite(_ id: String, _ data: Data, _ file: FileHandle, little: Bool) throws {
        guard data.count <= UInt32.max else { throw SourceMediaError.invalid("元数据过大。") }
        try file.write(contentsOf: Data(id.utf8) + bytes(UInt64(data.count), little: little) + data); if data.count & 1 == 1 { try file.write(contentsOf: Data([0])) }
    }
}
