import SwiftUI
import AppKit

struct ShortcutBinding: Codable, Equatable {
    var key: String
    var command = false
    var option = false
    var control = false
    var shift = false
    var flags: NSEvent.ModifierFlags {
        var f: NSEvent.ModifierFlags = []
        if command { f.insert(.command) }; if option { f.insert(.option) }
        if control { f.insert(.control) }; if shift { f.insert(.shift) }
        return f
    }
    var display: String {
        guard !key.isEmpty else { return "未设置" }
        let names = ["space": "空格", "left": "←", "right": "→", "delete": "⌫", "return": "↩"]
        return (control ? "⌃" : "") + (option ? "⌥" : "") + (shift ? "⇧" : "") + (command ? "⌘" : "") + (names[key] ?? key.uppercased())
    }
    var shortcut: KeyboardShortcut? {
        guard !key.isEmpty else { return nil }
        let k: KeyEquivalent
        switch key {
        case "space": k = .space
        case "left": k = .leftArrow
        case "right": k = .rightArrow
        case "delete": k = .delete
        case "return": k = .return
        default: guard key.count == 1, let c = key.first else { return nil }; k = KeyEquivalent(c)
        }
        var modifiers: EventModifiers = []
        if command { modifiers.insert(.command) }; if option { modifiers.insert(.option) }
        if control { modifiers.insert(.control) }; if shift { modifiers.insert(.shift) }
        return KeyboardShortcut(k, modifiers: modifiers)
    }
    static func capture(_ event: NSEvent) -> ShortcutBinding? {
        let f = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let special: [UInt16: String] = [49: "space", 123: "left", 124: "right", 51: "delete", 36: "return"]
        guard let key = special[event.keyCode] ?? event.charactersIgnoringModifiers?.lowercased(), !key.isEmpty else { return nil }
        return ShortcutBinding(key: key, command: f.contains(.command), option: f.contains(.option), control: f.contains(.control), shift: f.contains(.shift))
    }
    func matches(_ event: NSEvent) -> Bool { Self.capture(event) == self }
}

enum ShortcutAction: String, CaseIterable, Identifiable {
    case importFiles, importFolder, scan, importLyrics
    case library, collections, queue, playing, locate, newCollection, playCollection
    case playPause, previous, next, seekBack, seekForward, favorite, clearQueue, fullScreen, pictureInPicture
    case sideLyrics, menuLyrics, lyricBlur, lyricBackground, lyricEarlier, lyricLater, resetOffset, largerLyrics, smallerLyrics
    case selectAll, addToQueue, removeSelected
    var id: String { rawValue }
    var title: String {
        switch self {
        case .importFiles: return "导入文件"; case .importFolder: return "导入文件夹"
        case .scan: return "扫描已添加的文件夹"; case .importLyrics: return "导入字幕"
        case .library: return "资料库"; case .collections: return "我的合集"; case .queue: return "播放队列"; case .playing: return "正在播放"
        case .locate: return "定位当前播放"; case .newCollection: return "新建合集"; case .playCollection: return "播放整个合集"
        case .playPause: return "播放 / 暂停"; case .previous: return "上一首"; case .next: return "下一首"
        case .seekBack: return "快退5秒"; case .seekForward: return "快进5秒"; case .favorite: return "喜欢 / 取消喜欢"
        case .clearQueue: return "清空播放队列"; case .fullScreen: return "视频全屏"; case .pictureInPicture: return "画中画"
        case .sideLyrics: return "右侧歌词栏"; case .menuLyrics: return "菜单栏歌词"; case .lyricBlur: return "歌词模糊"
        case .lyricBackground: return "模糊封面作为背景"; case .lyricEarlier: return "歌词提前0.2秒"; case .lyricLater: return "歌词延后0.2秒"
        case .resetOffset: return "重置歌词同步"; case .largerLyrics: return "增大歌词字号"; case .smallerLyrics: return "减小歌词字号"
        case .selectAll: return "全选"; case .addToQueue: return "添加所选到队列"; case .removeSelected: return "移除所选项目"
        }
    }
    var group: String {
        switch self {
        case .importFiles, .importFolder, .scan, .importLyrics: return "文件"
        case .library, .collections, .queue, .playing, .locate: return "导航"
        case .newCollection, .playCollection, .selectAll, .addToQueue, .removeSelected: return "资料库与合集"
        case .sideLyrics, .menuLyrics, .lyricBlur, .lyricBackground, .lyricEarlier, .lyricLater, .resetOffset, .largerLyrics, .smallerLyrics: return "歌词"
        default: return "播放控制"
        }
    }
    var standard: ShortcutBinding {
        switch self {
        case .importFiles: return .init(key: "o", command: true)
        case .importFolder: return .init(key: "o", command: true, shift: true)
        case .scan: return .init(key: "r", command: true, shift: true)
        case .importLyrics: return .init(key: "l", command: true)
        case .library: return .init(key: "1", command: true)
        case .collections: return .init(key: "2", command: true)
        case .queue: return .init(key: "3", command: true)
        case .playing: return .init(key: "4", command: true)
        case .locate: return .init(key: "l", command: true, shift: true)
        case .newCollection: return .init(key: "n", command: true)
        case .playCollection: return .init(key: "p", command: true, shift: true)
        case .playPause: return .init(key: "space")
        case .previous: return .init(key: "left", command: true)
        case .next: return .init(key: "right", command: true)
        case .seekBack: return .init(key: "left")
        case .seekForward: return .init(key: "right")
        case .favorite: return .init(key: "d", command: true)
        case .clearQueue: return .init(key: "delete", command: true, shift: true)
        case .fullScreen: return .init(key: "f", command: true, control: true)
        case .pictureInPicture: return .init(key: "p", command: true, option: true)
        case .sideLyrics: return .init(key: "y", command: true, shift: true)
        case .menuLyrics: return .init(key: "m", command: true, shift: true)
        case .lyricBlur: return .init(key: "b", command: true, option: true)
        case .lyricBackground: return .init(key: "b", command: true, shift: true)
        case .lyricEarlier: return .init(key: "left", command: true, option: true)
        case .lyricLater: return .init(key: "right", command: true, option: true)
        case .resetOffset: return .init(key: "0", command: true, option: true)
        case .largerLyrics: return .init(key: "=", command: true)
        case .smallerLyrics: return .init(key: "-", command: true)
        case .selectAll: return .init(key: "a", command: true)
        case .addToQueue: return .init(key: "return", command: true)
        case .removeSelected: return .init(key: "delete")
        }
    }
}

@MainActor
final class ShortcutStore: ObservableObject {
    static let shared = ShortcutStore()
    @Published private(set) var overrides: [String: ShortcutBinding] = [:]
    private var observer: NSObjectProtocol?
    private let storageURL: URL
    init(url: URL? = nil) {
        storageURL = url ?? UserDataStore.shared.file("shortcuts.json")
        reload()
        observer = NotificationCenter.default.addObserver(forName: .myPlayerDataChanged, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated { if (note.object as? Set<String>)?.contains("shortcuts.json") == true { self?.reload() } }
        }
    }
    func binding(_ action: ShortcutAction) -> ShortcutBinding { overrides[action.rawValue] ?? action.standard }
    private func problem(_ value: ShortcutBinding, action: ShortcutAction, in values: [String: ShortcutBinding]) -> String? {
        guard !value.key.isEmpty else { return nil }
        guard value.shortcut != nil else { return "该按键暂不支持。" }
        if value.flags.intersection([.command, .option, .control]).isEmpty && !["space", "left", "right", "delete"].contains(value.key) { return "普通字符需要组合 Command、Option 或 Control，以免影响输入。" }
        let reserved = ["q", "w", "h", "m", "x", "c", "v", "z", ","]
        if (value.flags == .command && reserved.contains(value.key)) || (value.key == "z" && value.flags == [.command, .shift]) { return "此快捷键为系统或文本编辑保留。" }
        if action != .selectAll && value == ShortcutAction.selectAll.standard { return "Command+A 为全选保留。" }
        if let duplicate = ShortcutAction.allCases.first(where: { $0 != action && (values[$0.rawValue] ?? $0.standard) == value }) { return "与“\(duplicate.title)”重复。" }
        return nil
    }
    @discardableResult func set(_ value: ShortcutBinding, for action: ShortcutAction) -> String? {
        if let problem = problem(value, action: action, in: overrides) { return problem }
        overrides[action.rawValue] = value
        save(); return nil
    }
    @discardableResult func reset(_ action: ShortcutAction) -> String? {
        if let problem = problem(action.standard, action: action, in: overrides) { return problem }
        overrides.removeValue(forKey: action.rawValue); save(); return nil
    }
    func resetAll() { overrides = [:]; save() }
    private func save() { UserDataFiles.save(overrides, to: storageURL) }
    private func reload() {
        let url = storageURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let revision = UserDataFiles.revision(url)
            let saved = try JSONDecoder().decode([String: ShortcutBinding].self, from: Data(contentsOf: url))
            for action in ShortcutAction.allCases {
                if let error = problem(saved[action.rawValue] ?? action.standard, action: action, in: saved) { throw ShortcutLoadError.invalid(error) }
            }
            guard UserDataFiles.accept(url, expectedRevision: revision) else { return }
            overrides = saved
        } catch { UserDataStore.shared.report("shortcuts.json 无法应用：\(error.localizedDescription)。当前快捷键保留，原文件不会被覆盖。") }
    }
    private enum ShortcutLoadError: LocalizedError {
        case invalid(String)
        var errorDescription: String? { if case let .invalid(message) = self { return message }; return nil }
    }
}

private struct AppShortcut: ViewModifier {
    let action: ShortcutAction
    @ObservedObject private var store = ShortcutStore.shared
    func body(content: Content) -> some View { content.keyboardShortcut(store.binding(action).shortcut) }
}
extension View { func appShortcut(_ action: ShortcutAction) -> some View { modifier(AppShortcut(action: action)) } }

struct ShortcutEditorView: View {
    @ObservedObject private var store = ShortcutStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    var body: some View {
        VStack(spacing: 12) {
            HStack { Text("自定义快捷键").font(.title2.bold()); Spacer(); Button("完成") { dismiss() }.buttonStyle(.glassProminent).keyboardShortcut(.defaultAction) }
            Text("点击右侧快捷键后按下新组合；Esc 取消。修改会同步显示在菜单中。").foregroundStyle(.secondary)
            List {
                ForEach(["文件", "导航", "播放控制", "歌词", "资料库与合集"], id: \.self) { group in
                    Section(group) {
                        ForEach(ShortcutAction.allCases.filter { $0.group == group }) { action in
                            HStack {
                                Text(action.title); Spacer()
                                ShortcutRecorder(value: store.binding(action)) { value in error = store.set(value, for: action) }.frame(width: 160, height: 28)
                                Button { error = store.set(ShortcutBinding(key: ""), for: action) } label: { Image(systemName: "xmark.circle") }.help("清除此快捷键")
                                Button { RemovalConfirmation.request("移除自定义快捷键？", message: "将恢复此操作的默认快捷键。") { error = store.reset(action) } } label: { Image(systemName: "arrow.counterclockwise") }.help("恢复默认")
                            }.listRowSeparator(.hidden)
                        }
                    }
                }
            }
            HStack { if let error { Text(error).foregroundStyle(.red).lineLimit(2) }; Spacer(); Button("恢复全部默认") { store.resetAll(); error = nil } }
        }.padding(20).frame(width: 650, height: 600)
        .presentationSizing(.fitted).presentationBackground(.regularMaterial)
    }
}

private struct ShortcutRecorder: NSViewRepresentable {
    let value: ShortcutBinding
    let change: (ShortcutBinding) -> Void
    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.bezelStyle = .rounded
        button.target = button; button.action = #selector(RecorderButton.begin)
        return button
    }
    func updateNSView(_ view: RecorderButton, context: Context) {
        view.label = value.display; view.change = change
        if !view.recording { view.title = value.display }
    }
    final class RecorderButton: NSButton {
        var label = ""
        var change: ((ShortcutBinding) -> Void)?
        var recording = false
        private var monitor: Any?
        override var acceptsFirstResponder: Bool { true }
        @objc func begin() {
            recording = true; title = "请按快捷键…"
            window?.makeFirstResponder(self)
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.recording, self.window?.isKeyWindow == true, self.window?.firstResponder === self else { return event }
                if event.keyCode != 53, let binding = ShortcutBinding.capture(event) { self.change?(binding) }
                self.finish(); return nil
            }
        }
        private func finish() { recording = false; title = label; if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
        override func resignFirstResponder() -> Bool { finish(); return super.resignFirstResponder() }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if window == nil { finish() } }
    }
}
