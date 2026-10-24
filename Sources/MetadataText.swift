import Foundation
import CoreFoundation

enum MetadataText {
    static func repaired(_ value: String) -> String {
        let highBytes = value.unicodeScalars.filter { (0x80...0xff).contains($0.value) }.count
        guard highBytes >= 2, !containsEastAsian(value),
              let bytes = value.data(using: .isoLatin1, allowLossyConversion: false) else { return value }
        let gb = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        for encoding in [String.Encoding.utf8, gb] {
            if let candidate = String(data: bytes, encoding: encoding),
               containsEastAsian(candidate), !candidate.contains("�") {
                return candidate.precomposedStringWithCanonicalMapping
            }
        }
        return value
    }

    static func title(_ value: String, path: String, artist: String) -> String {
        let fixed = repaired(value)
        guard fixed.contains("??") || fixed.contains("�") || value.isEmpty else { return fixed }
        var filename = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent.precomposedStringWithCanonicalMapping
        guard !filename.contains("??"), !filename.contains("�"), !filename.isEmpty else { return fixed }
        if !artist.isEmpty {
            let suffix = "[-–—]\\s*" + NSRegularExpression.escapedPattern(for: artist) + "(?: \\d+)?$"
            filename = filename.replacingOccurrences(of: suffix, with: "", options: [.regularExpression, .caseInsensitive])
        }
        return filename.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func containsEastAsian(_ value: String) -> Bool {
        value.unicodeScalars.contains { (0x3400...0x9fff).contains($0.value) || (0xac00...0xd7af).contains($0.value) || (0x1100...0x11ff).contains($0.value) || (0x3040...0x30ff).contains($0.value) }
    }
}
