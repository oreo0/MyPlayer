import Foundation

enum RepeatMode: String, CaseIterable, Identifiable {
    case playOnce    // 单曲播放完暂停
    case repeatOne   // 单曲循环
    case repeatAll   // 列表循环

    enum NextAction { case pause, replay, advance }
    func nextAction(manual: Bool) -> NextAction {
        if manual { return .advance }
        switch self {
        case .playOnce: return .pause
        case .repeatOne: return .replay
        case .repeatAll: return .advance
        }
    }
    var id: String { rawValue }
    var label: String {
        switch self {
        case .playOnce: return "单曲播放后暂停"
        case .repeatOne: return "单曲循环"
        case .repeatAll: return "列表循环"
        }
    }
    var icon: String {
        switch self {
        case .playOnce: return "stop.circle"
        case .repeatOne: return "repeat.1"
        case .repeatAll: return "repeat"
        }
    }
}

// MARK: - 排序方式

enum SortKey: String, CaseIterable, Identifiable {
    case title, artist, album, playCount

    var id: String { rawValue }
    var label: String {
        switch self {
        case .title: return "文件"
        case .artist: return "艺人"
        case .album: return "专辑"
        case .playCount: return "播放次数"
        }
    }
}

