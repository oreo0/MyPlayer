import SwiftUI
import AppKit

enum ToolbarFeature: String, CaseIterable {
    case library, queue, playing, play, locate, lyricTiming, lyrics, split, artwork, menuLyrics, filter, view, sideLyrics, search
    static let groups: [(String, [ToolbarFeature])] = [
        ("页面导航", [.library, .queue, .playing]),
        ("播放与定位", [.play, .locate]),
        ("资料库显示", [.filter, .view, .sideLyrics]),
        ("播放页显示", [.lyrics, .split, .artwork]),
        ("歌词同步", [.lyricTiming]),
        ("通用工具", [.menuLyrics, .search])
    ]
    var title: String {
        switch self {
        case .library: "资料库"
        case .queue: "合集"
        case .playing: "正在播放"
        case .play: "播放"
        case .locate: "定位当前播放"
        case .lyricTiming: "歌词提前 / 延后"
        case .lyrics: "歌词 / 封面切换"
        case .split: "封面与歌词并排显示"
        case .artwork: "模糊封面作为背景（播放页与侧栏）"
        case .menuLyrics: "菜单栏歌词"
        case .filter: "筛选"
        case .view: "视图"
        case .sideLyrics: "侧边歌词"
        case .search: "搜索"
        }
    }
}

