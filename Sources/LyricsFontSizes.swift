import SwiftUI

enum LyricsSizeContext: String, CaseIterable, Identifiable {
    case sidebar, windowed, fullscreen
    var id: String { rawValue }
    var key: String { switch self { case .sidebar: "sidebarLyricsFontSize"; case .windowed: "windowLyricsFontSize"; case .fullscreen: "fullscreenLyricsFontSize" } }
    var title: String { switch self { case .sidebar: "侧边面板歌词字号"; case .windowed: "窗口播放页歌词字号"; case .fullscreen: "全屏播放页歌词字号" } }
}
enum LyricsFontSizes {
    @discardableResult static func migrate(_ defaults: UserDefaults) -> Bool {
        let old = defaults.object(forKey: "lyricsFontSize") as? Double ?? 28
        let value = old.isFinite ? min(72, max(28, old)) : 28
        var changed = false
        for context in LyricsSizeContext.allCases where defaults.object(forKey: context.key) == nil {
            defaults.set(value, forKey: context.key); changed = true
        }
        return changed
    }
}
private struct LyricsSizeEnvironmentKey: EnvironmentKey { static let defaultValue = LyricsSizeContext.sidebar }
extension EnvironmentValues {
    var lyricsSizeContext: LyricsSizeContext {
        get { self[LyricsSizeEnvironmentKey.self] }
        set { self[LyricsSizeEnvironmentKey.self] = newValue }
    }
}
private struct LyricsSizeFocusKey: FocusedValueKey { typealias Value = LyricsSizeContext }
extension FocusedValues {
    var lyricsSizeContext: LyricsSizeContext? {
        get { self[LyricsSizeFocusKey.self] }
        set { self[LyricsSizeFocusKey.self] = newValue }
    }
}
struct LyricsFontSizeMenu: View {
    let context: LyricsSizeContext
    @Binding var size: Double
    var body: some View {
        Menu("\(context.title)：\(Int(size))") {
            Button("增大") { size = min(72, size + 1) }.disabled(size >= 72)
            Button("减小") { size = max(28, size - 1) }.disabled(size <= 28)
            Divider()
            ForEach([28, 32, 36, 40, 48, 56, 64, 72], id: \.self) { value in
                Button { size = Double(value) } label: { Label("\(value)", systemImage: size == Double(value) ? "checkmark" : "") }
            }
        }
    }
}
