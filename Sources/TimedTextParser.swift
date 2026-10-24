import Foundation

enum TimedTextParser {
    static func parse(_ content: String) -> [LyricLine] {
        if !content.contains("-->") { return LRCParser.parse(content) }
        let lines = content.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: .newlines)
        var result: [LyricLine] = []
        var index = 0
        while index < lines.count {
            let bounds = lines[index].components(separatedBy: "-->")
            guard bounds.count == 2, let start = timestamp(bounds[0]), let end = timestamp(bounds[1]), end > start else { index += 1; continue }
            index += 1
            var text: [String] = []
            while index < lines.count && !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                text.append(lines[index]); index += 1
            }
            let cleaned = text.joined(separator: " ").replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty { result.append(LyricLine(time: start, text: cleaned, endTime: end)) }
        }
        return result.sorted { $0.time < $1.time }
    }
    private static func timestamp(_ value: String) -> Double? {
        guard let stamp = value.trimmingCharacters(in: .whitespaces).split(separator: " ").first else { return nil }
        let components = stamp.replacingOccurrences(of: ",", with: ".").split(separator: ":")
        let parts = components.compactMap { Double($0) }
        guard parts.count == components.count, parts.count == 2 || parts.count == 3,
              parts.allSatisfy({ $0.isFinite && $0 >= 0 }), let seconds = parts.last, seconds < 60 else { return nil }
        if parts.count == 3 && parts[1] >= 60 { return nil }
        return parts.reversed().enumerated().reduce(0) { $0 + $1.element * pow(60, Double($1.offset)) }
    }
    static func progress(lines: [LyricLine], index: Int, time: Double, offset: Double, duration: Double) -> Double {
        guard lines.indices.contains(index) else { return 0 }
        let line = lines[index]
        let end = line.endTime ?? (lines.indices.contains(index + 1) ? lines[index + 1].time : duration - offset)
        return min(1, max(0, (time - offset - line.time) / max(0.1, end - line.time)))
    }
}
