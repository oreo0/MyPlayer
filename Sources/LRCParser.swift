import Foundation

// MARK: - 歌词行模型

struct LyricLine: Identifiable, Equatable {
    let id = UUID()
    let time: TimeInterval
    let text: String
    var endTime: TimeInterval? = nil
}

// MARK: - LRC 歌词解析器

/// 解析标准 LRC 歌词，支持：
/// - 单行多时间戳：[00:12.00][01:30.50]同一句歌词
/// - 两位/三位小数（厘秒 / 毫秒）：[00:12.34] / [00:12:345]
/// - 元数据标签（[ti:] [ar:] [al:] 等）自动忽略
enum LRCParser {

    static func parse(_ content: String) -> [LyricLine] {
        var result: [LyricLine] = []
        guard let regex = try? NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]"#) else {
            return result
        }

        for rawLine in content.components(separatedBy: .newlines) {
            let ns = rawLine as NSString
            let matches = regex.matches(in: rawLine, range: NSRange(location: 0, length: ns.length))
            guard !matches.isEmpty else { continue }

            var text = rawLine
            var times: [TimeInterval] = []

            for match in matches.reversed() {
                let minute = Double(ns.substring(with: match.range(at: 1))) ?? 0
                let second = Double(ns.substring(with: match.range(at: 2))) ?? 0
                var fraction = 0.0
                if match.range(at: 3).location != NSNotFound {
                    let digits = ns.substring(with: match.range(at: 3))
                    fraction = (Double(digits) ?? 0) / pow(10, Double(digits.count))
                }
                times.append(minute * 60 + second + fraction)
                text = (text as NSString).replacingCharacters(in: match.range, with: "")
            }

            text = text.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            for t in times {
                result.append(LyricLine(time: t, text: text))
            }
        }

        return result.sorted { $0.time < $1.time }
    }

    /// 二分查找当前播放时间对应的歌词行索引
    static func currentIndex(for lyrics: [LyricLine], at time: TimeInterval) -> Int? {
        guard !lyrics.isEmpty else { return nil }
        var low = 0
        var high = lyrics.count - 1
        var answer: Int?
        while low <= high {
            let mid = (low + high) / 2
            if lyrics[mid].time <= time {
                answer = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return answer
    }
}
