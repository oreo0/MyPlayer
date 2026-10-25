import SwiftUI
import AppKit

// MARK: - 应用入口（MyPlayer）

@main
struct MyPlayerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var session = MyPlayerSession()
    @ObservedObject private var userData = UserDataStore.shared
    @State private var showShortcuts = false
    @AppStorage("themeColorName") private var themeName = ThemeColor.system.rawValue

    var body: some Scene {
        Window(AppVersion.name, id: "main") {
            Group {
            if let player = session.player, let collections = session.collections {
            ContentView()
                .environmentObject(player)
                .environmentObject(collections)
                .background(WindowLifecycleAnchor(appDelegate: appDelegate))
                .onAppear { appDelegate.player = player; appDelegate.collections = collections; appDelegate.hideFormatMenu() }
                .sheet(isPresented: $showShortcuts) { ShortcutEditorView() }
                .nativeDialog("用户数据未能应用", isPresented: Binding(get: { userData.issue != nil }, set: { if !$0 { userData.issue = nil } }), message: userData.issue ?? "")
                .tint(ThemeColor(rawValue: themeName)?.color)
                .accentColor(ThemeColor(rawValue: themeName)?.color)
            } else {
                VStack(spacing: 16) {
                    if let error = session.error {
                        Text("暂时无法恢复云端数据").font(.headline)
                        Text(error).foregroundStyle(.secondary)
                        Button("重试") { Task { await session.load() } }
                    } else {
                        ProgressView()
                        Text("正在准备用户数据…")
                    }
                }.padding(32).frame(minWidth: 480, minHeight: 240)
            }
            }.task { await session.load() }
        }
        .defaultSize(width: 1240, height: 780)
        .commands { MyPlayerCommands(session: session, showShortcuts: $showShortcuts) }
    }
}

private struct MyPlayerCommands: Commands {
    @ObservedObject var session: MyPlayerSession
    @ObservedObject private var cloudData = CloudDataController.shared
    @Binding var showShortcuts: Bool
    var body: some Commands {
            CommandGroup(replacing: .appInfo) {
                Button("关于 MyPlayer") {
                    let dark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
                    let url = Bundle.main.url(forResource: dark ? "AppIcon-dark" : "AppIcon-light", withExtension: "png")
                    let image = url.flatMap(NSImage.init(contentsOf:)) ?? NSImage(named: NSImage.applicationIconName) ?? NSImage()
                    NSApp.orderFrontStandardAboutPanel(options: [.applicationName: AppVersion.name, .applicationVersion: AppVersion.version, .version: "", .applicationIcon: image])
                }
            }
            CommandGroup(replacing: .appSettings) {
                Button("自定义快捷键…") { showShortcuts = true }.keyboardShortcut(",", modifiers: .command)
            }
            MinimalDefaultCommands()
            CommandGroup(replacing: .newItem) {
                if let player = session.player {
                Button("导入文件…") {
                    player.importAudioFiles()
                }
                .appShortcut(.importFiles)
                Button("导入文件夹…") {
                    player.importAudioFolder()
                }
                .appShortcut(.importFolder)
                Divider()
                Button(player.isScanningFolders ? "正在扫描已添加的文件夹…" : "扫描已添加的文件夹") { player.scanFolders() }
                    .appShortcut(.scan)
                    .disabled(player.isScanningFolders)
                Toggle("自动扫描已添加的文件夹", isOn: Binding(get: { player.autoScanFolders }, set: { player.autoScanFolders = $0 }))
                Menu("已添加的扫描文件夹") {
                    ForEach(player.watchedFolders) { folder in
                        Menu(folder.path) {
                            Button("在访达中显示") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: folder.path)]) }
                            Button("停止扫描此文件夹") { player.confirmStopWatchingFolder(folder) }
                        }
                    }
                }.disabled(player.watchedFolders.isEmpty)
                Divider()
                Button("打开用户数据文件夹") { NSWorkspace.shared.open(UserDataStore.shared.root) }
                Button("重新读取用户数据") { UserDataStore.shared.reloadNow() }
                Divider()
                Button("导入字幕…") {
                    player.importLyrics()
                }
                .appShortcut(.importLyrics)
                } else {
                    Button("导入文件…") {}.disabled(true)
                    Button("导入文件夹…") {}.disabled(true)
                    Text("正在准备用户数据…")
                }
                Divider()
                Menu("iCloud Drive") {
                    Text(cloudData.status)
                    Button("立即备份用户数据") { Task { await cloudData.syncNow() } }
                    Button("打开云端备份文件夹") { cloudData.openFolder() }
                    Text("音乐、视频原文件保留原位置")
                }
            }

        if let player = session.player { PlayerMenus(player: player) }
    }
}

// MARK: - 应用生命周期：外观模式 / 图标随系统外观切换

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var player: PlayerManager?
    weak var collections: CollectionStore?
    private var systemIconObserver: NSObjectProtocol?
    private var lastIconResource: String?
    private var windowLifecycle: MainWindowLifecycle?

    @MainActor func bindWindow(_ window: NSWindow) {
        if windowLifecycle?.window === window { return }
        windowLifecycle = MainWindowLifecycle(window: window, player: { [weak self] in self?.player })
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windowLifecycle?.restoreWindow()
        return true
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        let size = UserDefaults.standard.object(forKey: "lyricsFontSize") as? Double ?? 28
        if size < 28 || size > 72 { UserDefaults.standard.set(min(72, max(28, size)), forKey: "lyricsFontSize") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyAppearance()
        applyIconForCurrentAppearance()
        DispatchQueue.main.async { self.hideFormatMenu() }

        // 设置里的外观模式变化
        UserDefaults.standard.addObserver(self,
                                          forKeyPath: "appearanceMode",
                                          options: [.new],
                                          context: nil)
        systemIconObserver = DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyIconForCurrentAppearance() }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard player != nil else { return .terminateNow }
        player?.checkpointPlayback(flush: true)
        player?.flushLibrarySaves()
        collections?.flush()
        UserDataStore.shared.flush()
        Task { @MainActor in
            await CloudDataController.shared.syncNow()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        player?.checkpointPlayback(flush: true)
        player?.stopFolderScanning()
        player?.flushLibrarySaves()
        collections?.flush()
        UserDataStore.shared.flush()
        UserDefaults.standard.removeObserver(self, forKeyPath: "appearanceMode")
        if let systemIconObserver { DistributedNotificationCenter.default().removeObserver(systemIconObserver) }
    }

    override func observeValue(forKeyPath keyPath: String?,
                               of object: Any?,
                               change: [NSKeyValueChangeKey: Any]?,
                               context: UnsafeMutableRawPointer?) {
        DispatchQueue.main.async {
            self.applyAppearance()
        }
    }

    func hideFormatMenu() {
        // Hide only this unused top-level menu once, never delete items while
        // the user is tracking a menu (the old source of menu flashing).
        for item in NSApp.mainMenu?.items ?? [] {
            if ["Format", "格式"].contains(item.title) { item.isHidden = true }
            if ["View", "显示"].contains(item.title) { item.title = "外观" }
        }
    }

    /// 跟随系统 / 亮色 / 深色
    private func applyAppearance() {
        switch UserDefaults.standard.string(forKey: "appearanceMode") ?? "system" {
        case "light":
            if NSApp.appearance?.name != .aqua { NSApp.appearance = NSAppearance(named: .aqua) }
        case "dark":
            if NSApp.appearance?.name != .darkAqua { NSApp.appearance = NSAppearance(named: .darkAqua) }
        default:
            if NSApp.appearance != nil { NSApp.appearance = nil }
        }
    }

    /// 根据系统外观切换亮色/深色图标
    private func applyIconForCurrentAppearance() {
        let isDark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        let resource = isDark ? "AppIcon-dark" : "AppIcon-light"
        guard lastIconResource != resource else { return }
        lastIconResource = resource
        if let url = Bundle.main.url(forResource: resource, withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = image
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        UserDefaults.standard.string(forKey: "closeWindowBehavior") != "background"
    }
}

struct PlayerMenus: Commands {
    @FocusedValue(\.libraryActions) private var libraryActions
    @FocusedValue(\.collectionActions) private var collectionActions
    @ObservedObject var player: PlayerManager
    @AppStorage("themeColorName") private var theme = ThemeColor.system.rawValue
    @AppStorage("appearanceMode") private var appearance = "system"
    @AppStorage("betaVisualStyle") private var betaVisualStyle = "aurora"
    @AppStorage("desktopBackdropStyle") private var backdrop = "frosted"
    @AppStorage("lyricsArtworkBackground") private var lyricBackground = false
    @AppStorage("lyricsFontSize") private var lyricsSize = 28.0
    @AppStorage("lyricsBlurEnabled") private var lyricsBlur = false
    @AppStorage("lyricsCentered") private var lyricsCentered = true
    @AppStorage("showMenuBarLyrics") private var menuLyrics = true
    @AppStorage("lyricsFontWeight") private var lyricsWeight = "bold"
    @AppStorage("libraryViewStyle") private var libraryViewStyle = "list"
    @AppStorage("showLibraryLyrics") private var showLibraryLyrics = true
    @AppStorage("lyricsFontName") private var lyricsFont = "system"
    @AppStorage("videoLyricsStyle") private var videoLyricsStyle = "single"
    @AppStorage("videoLyricsSize") private var videoLyricsSize = 30.0
    @AppStorage("videoLyricsWeight") private var videoLyricsWeight = "bold"
    @AppStorage("videoLyricsFont") private var videoLyricsFont = "system"
    @AppStorage("closeWindowBehavior") private var closeWindowBehavior = "quit"
    var body: some Commands {
        CommandGroup(replacing: .toolbar) {
            Picker("界面外观", selection: $appearance) {
                Text("跟随系统").tag("system")
                Text("浅色").tag("light")
                Text("深色").tag("dark")
            }
            Picker("主题色", selection: $theme) {
                ForEach(ThemeColor.allCases) { color in Text(color.label).tag(color.rawValue) }
            }
            Picker("背景光效", selection: $betaVisualStyle) {
                Text("极光流动").tag("aurora")
                Text("柔和光晕").tag("halo")
                Text("关闭光效").tag("off")
            }
            Picker("背景效果", selection: $backdrop) {
                Text("毛玻璃").tag("frosted")
                Text("深层磨砂").tag("gaussian")
                Text("纯色").tag("solid")
            }
            Divider()
            Picker("资料库视图", selection: $libraryViewStyle) {
                Text("列表").tag("list")
                Text("封面").tag("covers")
            }
        }
        CommandMenu("歌词") {
            Toggle("右侧歌词栏", isOn: $showLibraryLyrics).appShortcut(.sideLyrics)
            Divider()
                Button("歌词提前 0.2 秒") { player.adjustLyrics(by: -0.2) }.appShortcut(.lyricEarlier).disabled(player.lyrics.isEmpty)
                Button("歌词延后 0.2 秒") { player.adjustLyrics(by: 0.2) }.appShortcut(.lyricLater).disabled(player.lyrics.isEmpty)
                Button("重置歌词同步") { player.resetLyricsOffset() }.appShortcut(.resetOffset).disabled(player.nowPlaying == nil)
            Divider()
            Toggle("歌词模糊", isOn: $lyricsBlur).appShortcut(.lyricBlur)
            Toggle("歌词居中", isOn: $lyricsCentered)
            Toggle("菜单栏歌词", isOn: $menuLyrics).appShortcut(.menuLyrics)
            Toggle("模糊封面作为背景", isOn: $lyricBackground).appShortcut(.lyricBackground)
            Picker("歌词字体", selection: $lyricsFont) {
                Text("系统字体").tag("system")
                ForEach(NSFontManager.shared.availableFontFamilies.sorted(), id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            Menu("歌词字号：\(Int(lyricsSize))") {
                Button("增大") { lyricsSize = min(72, lyricsSize + 1) }
                    .appShortcut(.largerLyrics)
                    .disabled(lyricsSize >= 72)
                Button("减小") { lyricsSize = max(28, lyricsSize - 1) }
                    .appShortcut(.smallerLyrics)
                    .disabled(lyricsSize <= 28)
                Divider()
                ForEach([28, 32, 36, 40, 48, 56, 64, 72], id: \.self) { size in
                    Button { lyricsSize = Double(size) } label: {
                        Label("\(size)", systemImage: lyricsSize == Double(size) ? "checkmark" : "")
                    }
                }
            }
            Picker("歌词字重", selection: $lyricsWeight) {
                ForEach(LyricsWeight.allCases) { weight in Text(weight.label).tag(weight.rawValue) }
            }
            Divider()
            Section("视频字幕") {
            Picker("视频字幕字体", selection: $videoLyricsFont) {
                Text("系统字体").tag("system")
                ForEach(NSFontManager.shared.availableFontFamilies.sorted(), id: \.self) { name in Text(name).tag(name) }
            }
            Picker("视频字幕显示方式", selection: $videoLyricsStyle) {
                Text("居中单行").tag("single")
                Text("KTV 双行左右分离").tag("ktv")
            }
            Picker("视频字幕字号", selection: $videoLyricsSize) {
                ForEach([28, 30, 32, 36, 42, 48, 56, 64, 72], id: \.self) { size in Text("\(size)").tag(Double(size)) }
            }
            Picker("视频字幕字重", selection: $videoLyricsWeight) {
                ForEach(LyricsWeight.allCases) { weight in Text(weight.label).tag(weight.rawValue) }
            }
            }
        }
        CommandGroup(replacing: .windowArrangement) {
            Picker("关闭窗口后", selection: $closeWindowBehavior) {
                Text("退出应用").tag("quit")
                Text("后台继续播放").tag("background")
            }
            Divider()
            Button("资料库") { NotificationCenter.default.post(name: .myPlayerNavigate, object: "library") }.appShortcut(.library)
            Button("我的合集") { NotificationCenter.default.post(name: .myPlayerNavigate, object: "collections") }.appShortcut(.collections)
            Button("播放队列") { NotificationCenter.default.post(name: .myPlayerNavigate, object: "queue") }.appShortcut(.queue)
            Button("正在播放") { NotificationCenter.default.post(name: .myPlayerNavigate, object: "playing") }.appShortcut(.playing)
        }
        CommandGroup(replacing: .help) {
            Button("向开发者提交建议或反馈") {
                var url = URLComponents()
                url.scheme = "mailto"
                url.path = "fight1212@outlook.com"
                url.queryItems = [URLQueryItem(name: "subject", value: "MyPlayer 问题反馈")]
                if let url = url.url { NSWorkspace.shared.open(url) }
            }
        }
        CommandMenu("资料库") {
            Button("定位当前播放") { NotificationCenter.default.post(name: .locateCurrentMedia, object: nil) }
                .appShortcut(.locate).disabled(player.nowPlaying == nil)
            Button("新建合集…") { collectionActions?.create() }.appShortcut(.newCollection).disabled(collectionActions == nil)
            Button("播放整个合集") { collectionActions?.play() }.appShortcut(.playCollection).disabled(collectionActions?.canPlay != true)
            Divider()
            Button("全选") {
                if let text = NSApp.keyWindow?.firstResponder as? NSTextView { text.selectAll(nil) }
                else if let libraryActions { libraryActions.selectAll() }
            }.appShortcut(.selectAll)
            Button("添加所选到播放队列") { libraryActions?.addToQueue() }.appShortcut(.addToQueue)
                .disabled(libraryActions?.hasSelection != true)
            Button("从当前列表移除所选") { libraryActions?.remove() }.appShortcut(.removeSelected)
                .disabled(libraryActions?.hasSelection != true)

        }
        CommandMenu("控制") {
            Button(player.isPlaying ? "暂停" : "播放", action: player.togglePlayPause)
                .appShortcut(.playPause)
            Button("上一首", action: player.playPrevious).appShortcut(.previous)
            Button("下一首") { player.playNext(manual: true) }.appShortcut(.next)
            Divider()
            Button("快退 5 秒") { player.seek(to: player.currentTime - 5) }.appShortcut(.seekBack)
            Button("快进 5 秒") { player.seek(to: player.currentTime + 5) }.appShortcut(.seekForward)
            Divider()
            Picker("播放模式", selection: $player.repeatMode) {
                ForEach(RepeatMode.allCases) { mode in Text(mode.label).tag(mode) }
            }
            Button(player.nowPlaying?.isFavorite == true ? "取消喜欢" : "喜欢") {
                if let song = player.nowPlaying { player.confirmToggleFavorite(song) }
            }.appShortcut(.favorite).disabled(player.nowPlaying == nil)
            Button("清空播放队列", action: player.confirmClearQueue).appShortcut(.clearQueue).disabled(player.upNext.isEmpty)
            Divider()
            Button("视频全屏 / 退出全屏") { VideoPresentation.shared.toggleFullScreen() }.appShortcut(.fullScreen)
                .disabled(!player.isVideo)
            Button("画中画 / 退出画中画") { VideoPresentation.shared.togglePictureInPicture() }.appShortcut(.pictureInPicture)
                .disabled(!player.isVideo)
        }
    }
}

/// Remove unsupported commands declaratively, before menus are opened. Do not
/// mutate NSMenu in didAddItem notifications while AppKit is tracking a menu.
private struct MinimalDefaultCommands: Commands {
    var body: some Commands {
        editing
        windows
        unused
    }
    @CommandsBuilder private var editing: some Commands {
        CommandGroup(replacing: .undoRedo) { }
        CommandGroup(replacing: .pasteboard) { }
        CommandGroup(replacing: .textEditing) { }
        CommandGroup(replacing: .textFormatting) { }
    }
    @CommandsBuilder private var windows: some Commands {
        CommandGroup(replacing: .sidebar) { }
        CommandGroup(replacing: .windowSize) { }
        CommandGroup(replacing: .windowList) { }
        CommandGroup(replacing: .singleWindowList) { }
    }
    @CommandsBuilder private var unused: some Commands {
        CommandGroup(replacing: .saveItem) { }
        CommandGroup(replacing: .printItem) { }
        CommandGroup(replacing: .importExport) { }
        CommandGroup(replacing: .systemServices) { }
    }
}
