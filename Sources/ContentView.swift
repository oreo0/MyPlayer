import SwiftUI
import AppKit
import AVKit
import UniformTypeIdentifiers

enum MusicPage: String, CaseIterable, Identifiable {
    case library, favorites, queue, playing, collections
    var id: String { rawValue }
    var title: String {
        switch self {
        case .library: "资料库"
        case .favorites: "我喜欢"
        case .queue: "播放队列"
        case .collections: "合集"
        case .playing: "正在播放"
        }
    }
    var icon: String {
        switch self {
        case .library: "music.note.house"
        case .favorites: "heart"
        case .queue: "list.bullet"
        case .collections: "rectangle.stack"
        case .playing: "waveform"
        }
    }
}

enum MediaFilter: String, CaseIterable, Identifiable {
    case all = "全部", audio = "歌曲", video = "视频"
    var id: String { rawValue }
    func includes(_ song: Song) -> Bool { self == .all || (self == .video ? song.isVideo : !song.isVideo) }
}

struct ContentView: View {
    @State private var coverBackTitle: String?
    @State private var libraryPage: MusicPage = .library
    @StateObject private var libraryScrollMemory = ScrollPositionMemory()
    @StateObject private var collectionScrollMemory = ScrollPositionMemory()
    private func shows(_ feature: ToolbarFeature) -> Bool { true }
    @AppStorage("showLibraryLyrics") private var showLibraryLyrics = true
    @AppStorage("coverSortAscending") private var coverSortAscending = true
    @AppStorage("coverGrouping") private var coverGroupingRaw = "album"
    @AppStorage("libraryViewStyle") private var libraryViewStyle = "list"
    private let themeName = "media"
    private let followsMedia = true
    private var effectiveAccent: Color {
        if followsMedia || page == .playing { return (page == .playing ? playingAccent : (hasArtwork ? sidebarAppearance.accent : playbackAppearance.accent)) ?? ThemeColor.current.color ?? Color(nsColor: .controlAccentColor) }
        return ThemeColor.current.color ?? Color(nsColor: .controlAccentColor)
    }
    @State private var showQueue = false
    @State private var nativeTopInset: CGFloat = 0
    @State private var sidePanelWidth: CGFloat = 0
    @AppStorage("sidePanelPreferredWidth") private var savedPanelWidth = 0.0
    private func panelWidth(_ width: CGFloat, overlay: Bool = false) -> CGFloat {
        SidePanelMetrics.resolvedWidth(for: width, preferred: sidePanelWidth > 0 ? sidePanelWidth : CGFloat(savedPanelWidth), overlay: overlay)
    }
    private func setQueueVisible(_ visible: Bool) {
        var transaction = Transaction(animation: reduceMotion ? nil : .smooth(duration: 0.3))
        transaction.disablesAnimations = false
        withTransaction(transaction) { showQueue = visible }
    }

    private let interaction = InteractionActivity.shared
    @State private var heldChrome: Bool?
    @State private var controlsOverride: Bool?
    @State private var activePointerInside = false
    @State private var windowIsFullScreen = false
    @State private var playerBarHeight: CGFloat = 110
    @State private var videoControlsVisible = false
    @State private var videoHideTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var barVisible: Bool {
        if page != .playing { return true }
        if let heldChrome { return heldChrome }
        if let controlsOverride { return controlsOverride }
        return activePointerInside && videoControlsVisible
    }
    private var playerBarPresented: Bool {
        page == .playing ? (barVisible && !(player.isVideo && videoLyricsEnabled && !player.lyrics.isEmpty)) : (showLibraryLyrics && !showQueue && windowWidth >= 850)
    }
    @AppStorage("videoLyricsEnabled") private var videoLyricsEnabled = false
    @StateObject private var sidebarAppearance = ArtworkSurfaceAppearance()
    @StateObject private var playbackAppearance = PlaybackAppearance()
    @StateObject private var applicationAppearance = ApplicationAppearance()
    private var applicationScheme: ColorScheme { applicationAppearance.scheme }
    @State private var hasArtwork = false
    @State private var artworkRevision = 0
    @AppStorage("nowPlayingSplitView") private var splitView = false
    private var usesCoverBackdrop: Bool { hasArtwork && !player.isVideo && lyricsArtworkBackground }
    private var sidebarScheme: ColorScheme { lyricsArtworkBackground && hasArtwork ? sidebarAppearance.scheme : applicationScheme }
    private var sidebarAccent: Color? { lyricsArtworkBackground && hasArtwork ? (sidebarAppearance.accent ?? effectiveAccent) : effectiveAccent }
    private var playingAccent: Color? { hasArtwork ? sidebarAppearance.accent : playbackAppearance.accent }
    private var playingScheme: ColorScheme { usesCoverBackdrop ? sidebarAppearance.scheme : (!player.isVideo && !usesCoverBackdrop ? applicationScheme : playbackAppearance.scheme) }
    private var toolbarForeground: Color {
        guard page == .playing else { return .primary }
        return playingScheme == .light ? .black : .white
    }
    @State private var mediaFilter = MediaFilter.all
    @EnvironmentObject private var player: PlayerManager
    @State private var page: MusicPage? = .library
    @State private var search = ""
    @State private var windowWidth: CGFloat = 1240
    @State private var searchExpanded = true
    @FocusState private var searchFocused: Bool
    @AppStorage("lyricsArtworkBackground") private var lyricsArtworkBackground = false
    @State private var menuBarController: MenuBarLyricsController?
    @AppStorage("showMenuBarLyrics") private var showMenuBarLyrics = true
    @AppStorage("desktopBackdropStyle") private var material = "frosted"
    @AppStorage("nowPlayingShowsLyrics") private var showsLyrics = true

    private var visibleSongs: [Song] {
        let source: [Song]
        switch page {
        case .queue: source = player.queuedSongs
        case .favorites: source = player.sortedLibrary.filter(\.isFavorite)
        default: source = player.sortedLibrary
        }
        if (page == .queue || mediaFilter == .all) && search.isEmpty { return source }
        return source.filter { (page == .queue || mediaFilter.includes($0)) && (search.isEmpty || "\($0.title) \($0.artist) \($0.album)".localizedStandardContains(search)) }
    }
    private var title: String {
        let selected = page ?? .library
        if selected == .collections { return "合集" }
        return selected == .playing ? selected.title : "\(selected.title) · \(visibleSongs.count) 个文件"
    }

    var body: some View {
        windowContent
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("MyPlayer.coverNavigationChanged"))) { event in
            coverBackTitle = event.object as? String
        }
        .onAppear {
            if menuBarController == nil { menuBarController = MenuBarLyricsController.shared(for: player) }
        }
        .onChange(of: player.nowPlaying?.artworkID, initial: true) { _, _ in
            hasArtwork = player.nowPlaying?.hasArtwork == true
            artworkRevision += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .myPlayerNavigate)) { event in
            switch event.object as? String {
            case "library": selectTab(.library)
            case "queue": setQueueVisible(true); controlsOverride = true
            case "collections": selectTab(.collections)
            case "playing": selectTab(.playing)
            default: break
            }
        }
        .onChange(of: showMenuBarLyrics) { _, visible in menuBarController?.setVisible(visible) }
        .onChange(of: player.nowPlaying?.id) { _, _ in if player.isVideo { selectTab(.playing) } }
        .onChange(of: player.isVideo, initial: true) { _, video in if video { selectTab(.playing) } }
        .onChange(of: page) { _, value in if let value, value == .library || value == .favorites { libraryPage = value }; controlsOverride = nil; videoHideTask?.cancel(); if value == .playing { showVideoControls() } }
        .onReceive(interaction.$isTrackingMenu.combineLatest(interaction.$isEditingMetadata).map { $0 || $1 }.removeDuplicates()) { holding in
            guard page == .playing else { return }
            if holding { heldChrome = barVisible; videoHideTask?.cancel() }
            else { heldChrome = nil; if page == .playing { showVideoControls() } }
        }
        .onDisappear { videoHideTask?.cancel() }
        .focusedSceneValue(\.lyricsSizeContext, page == .playing ? (windowIsFullScreen ? .fullscreen : .windowed) : .sidebar)
    }
    private var windowContent: some View {
        navigationContent
        .onGeometryChange(for: CGFloat.self) { $0.size.width < 850 ? 800 : ($0.size.width < 1100 ? 1000 : 1240) } action: { windowWidth = $0 }
        .overlay(alignment: .bottom) {
            GeometryReader { geometry in
                let playing = page == .playing
                let panelWidth = self.panelWidth(geometry.size.width)
                let width = playing ? geometry.size.width * (2.0 / 3.0) : max(1, panelWidth - 32)
                NativePlayerBar(player: player, isActive: playerBarPresented, showPlaying: { selectTab(.playing) }, queueVisible: showQueue, toggleQueue: { setQueueVisible(!showQueue) }, showThumbnail: page != .playing || (!splitView && showsLyrics) || player.isVideo || !hasArtwork, compact: !playing, videoFullScreen: windowIsFullScreen)
                    .environment(\.colorScheme, playing ? playingScheme : sidebarScheme)
                    .environment(\.playbackAccent, playing ? playingAccent : sidebarAccent)
                    .tint(playing ? effectiveAccent : (sidebarAccent ?? effectiveAccent))
                    .frame(width: width)
                    .background(CanvasClickPassthrough(enabled: playing && playerBarPresented))
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { playerBarHeight = $0 }
                    .offset(x: !playing && (!showLibraryLyrics || showQueue) ? panelWidth : 0)
                    .opacity(playerBarPresented ? 1 : 0)
                    .allowsHitTesting(playerBarPresented)
                    .accessibilityHidden(!playerBarPresented)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: playing ? .bottom : .bottomTrailing)
                    .padding(.trailing, playing ? 0 : 16)
                    .padding(.bottom, playing ? 12 : 20)
                    
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: playerBarPresented)
                    .transaction(value: playing) { transaction in
                        transaction.animation = nil; transaction.disablesAnimations = true
                    }
            }
        }
        .toolbar(page == .playing && !barVisible && !windowIsFullScreen ? .hidden : .visible, for: .windowToolbar)
        .tint(effectiveAccent)
        .accentColor(effectiveAccent)
        .environment(\.playbackAccent, page == .playing ? playingAccent : (followsMedia ? playbackAppearance.accent : nil))
        .environment(\.ambientArtworkColors, sidebarAppearance.ambientColors)
        .environment(\.colorScheme, page == .playing ? playingScheme : applicationScheme)
        .preferredColorScheme(page == .playing ? playingScheme : applicationScheme)
        .toolbarColorScheme(page == .playing ? playingScheme : applicationScheme, for: .windowToolbar)
        .background(PlaybackToolbarPresentation(toolbarVisible: page != .playing, controlsVisible: barVisible, reduceMotion: reduceMotion, hideWindowChrome: page == .playing && !barVisible))
        .task(id: "sidebar-\(artworkRevision)-\(applicationScheme)") {
            await sidebarAppearance.update(player.nowPlaying?.artworkData, fallback: applicationScheme)
        }
        .task(id: appearanceTaskKey) {
            await playbackAppearance.observe(song: player.nowPlaying, video: player.videoPlayer, active: player.isVideo || page == .playing || followsMedia, darkLyrics: (showsLyrics || splitView) && usesCoverBackdrop, defaultScheme: !player.isVideo && (page != .playing || !usesCoverBackdrop) ? applicationScheme : nil, shouldSample: { !interaction.holdsAutoHide && !hasArtwork && (followsMedia || (page == .playing && barVisible)) })
        }
        .ignoresSafeArea(.container, edges: page == .playing ? .top : [])
        .background { if page == .playing && player.isVideo { Color.black.ignoresSafeArea() } }
        .containerBackground(.clear, for: .window)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .background { if !player.isVideo && !lyricsArtworkBackground { BetaAmbientLight(colors: sidebarAppearance.ambientColors, playing: player.isPlaying).ignoresSafeArea() } }
        .background { NativeWindowBackground(material: material).ignoresSafeArea() }
        .frame(minWidth: 800, minHeight: 560)
        .background(WindowInteraction(hideCursor: page == .playing && !barVisible, onActivity: showVideoControls, onCanvasClick: toggleCanvasControls, onFullScreenChange: { windowIsFullScreen = $0 }) { inside in
            activePointerInside = inside
            if inside { if controlsOverride != false { showVideoControls() } } else { videoHideTask?.cancel() }
        })
        .background(SeekKeyboard(player: player).frame(width: 0, height: 0))
        .background(WindowContentTopInset { nativeTopInset = $0 })
        .overlay(alignment: .topLeading) {
            if let activity = player.libraryActivity, page != .playing {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text(activity).font(.caption) }
                    .padding(10).background(.regularMaterial, in: Capsule()).padding(12)
            }
        }
        .nativeDialog(player.playbackError == nil ? "资料库" : "无法播放", isPresented: Binding(get: {
            player.playbackError != nil || player.libraryImportMessage != nil
        }, set: { if !$0 { player.playbackError = nil; player.libraryImportMessage = nil } }),
        message: [player.playbackError, player.libraryImportMessage].compactMap { $0 }.joined(separator: "\n\n"))
    }

    private var navigationContent: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    HStack(spacing: 0) {
                        ZStack {
                            NativeLibrary(scrollMemory: libraryScrollMemory, page: libraryPage, search: search, mediaFilter: mediaFilter, bottomClearance: 12, isActive: page != .playing && page != .collections)
                                .opacity(page == .collections ? 0 : 1)
                                .allowsHitTesting(page != .collections && page != .playing)
                                .accessibilityHidden(page == .collections || page == .playing)
                            CollectionsView(scrollMemory: collectionScrollMemory, isActive: page == .collections, bottomClearance: 12)
                                .opacity(page == .collections ? 1 : 0)
                                .allowsHitTesting(page == .collections)
                                .accessibilityHidden(page != .collections)
                        }
                        .frame(minWidth: min(450, geometry.size.width), maxWidth: .infinity, maxHeight: .infinity)
                        if geometry.size.width >= 850 && (showLibraryLyrics || showQueue) {
                            Group {
                                if showQueue { QueuePanel(player: player, isActive: page != .playing, bottomClearance: 12) { setQueueVisible(false) } }
                                else {
                                    SideLyricsPanel(player: player, isActive: page != .playing)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(8)
                            .background {
                                if page != .playing && !showQueue && lyricsArtworkBackground && hasArtwork {
                                    LyricsArtworkBackground(song: player.nowPlaying, dimming: sidebarAppearance.scheme == .dark ? 0.3 : 0.02)
                                }
                            }
                            .background(.regularMaterial, in: .rect(cornerRadius: SurfaceCorners.panel))
                            .clipShape(.rect(cornerRadius: SurfaceCorners.panel))
                            .environment(\.colorScheme, showQueue ? applicationScheme : sidebarScheme)
                            .environment(\.playbackAccent, showQueue ? nil : sidebarAccent)
                            .tint(showQueue ? effectiveAccent : (sidebarAccent ?? effectiveAccent))
                            .padding(8)
                            .frame(width: self.panelWidth(geometry.size.width))
                            .overlay(alignment: .leading) { panelResizeHandle(windowWidth: geometry.size.width, overlay: false) }
                            .frame(maxHeight: .infinity)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                    .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: showLibraryLyrics || showQueue)
                    .environment(\.colorScheme, applicationScheme)
                    .opacity(page == .playing ? 0 : 1)
                    .allowsHitTesting(page != .playing)
                    .accessibilityHidden(page == .playing)
                    NativeNowPlaying(player: player, showsLyrics: showsLyrics, splitView: splitView, isActive: page == .playing, hasArtwork: hasArtwork, chromeVisible: barVisible, coverTopClearance: 84, coverBottomClearance: playerBarHeight + 36)
                            .environment(\.lyricsSizeContext, windowIsFullScreen ? .fullscreen : .windowed)
                            .environment(\.colorScheme, playingScheme)
                            .ignoresSafeArea(.container, edges: .top)
                            .opacity(page == .playing ? 1 : 0)
                            .allowsHitTesting(page == .playing)
                            .accessibilityHidden(page != .playing)
                    if showQueue && (page == .playing || geometry.size.width < 850) {
                        HStack(spacing: 0) {
                            Spacer(minLength: 0)
                            QueuePanel(player: player, bottomClearance: page == .playing ? playerBarHeight + 28 : 12) { setQueueVisible(false) }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding(8)
                                .background(.regularMaterial, in: .rect(cornerRadius: SurfaceCorners.panel))
                                .clipShape(.rect(cornerRadius: SurfaceCorners.panel))
                                .padding(8)
                                .frame(width: self.panelWidth(geometry.size.width))
                                .overlay(alignment: .leading) { panelResizeHandle(windowWidth: geometry.size.width, overlay: false) }
                        }
                        .padding(.top, page == .playing ? nativeTopInset : 0)
                        .environment(\.colorScheme, applicationScheme)
                        .opacity(page == .playing && !barVisible ? 0 : 1)
                        .allowsHitTesting(page != .playing || barVisible)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                        .zIndex(20)
                    }
                }
                .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: showQueue)
            }
            .navigationTitle(page == .playing ? "" : title)

            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    if libraryViewStyle == "covers", page == .library || page == .favorites, let title = coverBackTitle {
                        Button {
                            NotificationCenter.default.post(name: Notification.Name("MyPlayer.resetCoverBrowsing"), object: nil)
                        } label: { Label(title, systemImage: "chevron.left") }
                        .labelStyle(.iconOnly).help("返回" + title)
                        .foregroundStyle(toolbarForeground)
                        .modifier(ToolbarControlVisibility(visible: barVisible, reduceMotion: reduceMotion))
                    }
                    Button("资料库", systemImage: "music.note.house") {
                        selectTab(.library)
                    }
                    .labelStyle(.iconOnly).help("资料库")
                    .modifier(ToolbarTabHighlight(selected: page == .library || page == .favorites, accent: effectiveAccent))
                    .foregroundStyle(toolbarForeground)
                    .modifier(ToolbarControlVisibility(visible: barVisible, reduceMotion: reduceMotion))
                    Button("合集", systemImage: "rectangle.stack") { selectTab(.collections) }
                        .labelStyle(.iconOnly).help("合集")
                        .modifier(ToolbarTabHighlight(selected: page == .collections, accent: effectiveAccent))
                        .foregroundStyle(toolbarForeground)
                        .modifier(ToolbarControlVisibility(visible: barVisible, reduceMotion: reduceMotion))
                }.sharedBackgroundVisibility(page == .playing && windowIsFullScreen ? .hidden : (barVisible ? .automatic : .hidden))
                ToolbarSpacer(.fixed, placement: .navigation)
                ToolbarItem(placement: .navigation) {
                    if shows(.playing) { playingEntry.foregroundStyle(toolbarForeground).environment(\.colorScheme, page == .playing ? playingScheme : applicationScheme).modifier(ToolbarControlVisibility(visible: barVisible, reduceMotion: reduceMotion)) }
                }.sharedBackgroundVisibility(page == .playing && windowIsFullScreen ? .hidden : (barVisible ? .automatic : .hidden))
                ToolbarSpacer(.flexible, placement: .primaryAction)
                ToolbarItemGroup(placement: .primaryAction) {
                    if page != .playing { toolbarControls { libraryToolbarControls } }
                }.sharedBackgroundVisibility(page == .playing && windowIsFullScreen ? .hidden : (barVisible ? .automatic : .hidden))
                ToolbarSpacer(.fixed, placement: .primaryAction)
                ToolbarItemGroup(placement: .primaryAction) {
                    if page == .collections || page == .library || page == .favorites || page == nil { toolbarControls { collectionToolbarControls } }
                }.sharedBackgroundVisibility(page == .playing && windowIsFullScreen ? .hidden : (barVisible ? .automatic : .hidden))
                ToolbarSpacer(.fixed, placement: .primaryAction)
                ToolbarItemGroup(placement: .primaryAction) {
                    // Timing adjustments remain available in the Lyrics menu.
                }.sharedBackgroundVisibility(page == .playing && windowIsFullScreen ? .hidden : (barVisible ? .automatic : .hidden))
                ToolbarSpacer(.fixed, placement: .primaryAction)
                ToolbarItemGroup(placement: .primaryAction) {
                    toolbarControls { displayToolbarControls }
                }.sharedBackgroundVisibility(page == .playing && windowIsFullScreen ? .hidden : (barVisible ? .automatic : .hidden))
                ToolbarSpacer(.fixed, placement: .primaryAction)
                ToolbarItem(id: "search", placement: .primaryAction) {
                    if page != .playing && shows(.search) { searchControl.foregroundStyle(toolbarForeground).tint(toolbarForeground).environment(\.colorScheme, page == .playing ? playingScheme : applicationScheme).modifier(ToolbarControlVisibility(visible: barVisible, reduceMotion: reduceMotion)) }
                }.sharedBackgroundVisibility(page == .playing && windowIsFullScreen ? .hidden : (barVisible ? .automatic : .hidden))
            }
        }

    }

    private func toolbarControls<Controls: View>(@ViewBuilder content: () -> Controls) -> some View {
        Group(content: content)
            .labelStyle(.iconOnly)
            .foregroundStyle(toolbarForeground)
            .environment(\.colorScheme, page == .playing ? playingScheme : applicationScheme)
            .modifier(ToolbarControlVisibility(visible: barVisible, reduceMotion: reduceMotion))
    }

    private func selectTab(_ target: MusicPage) {
        switch TabNavigation.action(from: page, to: target) {
        case .activate(let destination):
            let next = destination == .library ? libraryPage : destination
            guard next != page else { return }
            libraryScrollMemory.suspend(); collectionScrollMemory.suspend()
            page = next
        case .libraryHome:
            libraryScrollMemory.resetToTop("covers:library:\(coverGroupingRaw):root")
            libraryPage = .library; page = .library; mediaFilter = .all; search = ""
            NotificationCenter.default.post(name: .libraryHome, object: nil)
        case .collectionsHome:
            NotificationCenter.default.post(name: .collectionsHome, object: nil)
        }
    }

    private func panelResizeHandle(windowWidth: CGFloat, overlay: Bool) -> some View {
        PanelResizeHandle(width: Binding(get: { panelWidth(windowWidth, overlay: overlay) }, set: { sidePanelWidth = $0 }),
                          limits: SidePanelMetrics.limits(for: windowWidth, overlay: overlay),
                          onEnd: { savedPanelWidth = Double(sidePanelWidth) })
    }

    private var appearanceTaskKey: String {
        if let item = player.videoPlayer?.currentItem { return "video-\(ObjectIdentifier(item))" }
        return "\(page == .playing)-\(player.nowPlaying?.id.uuidString ?? "none")-\(artworkRevision)-\(showsLyrics)-\(splitView)-\(lyricsArtworkBackground)-\(applicationScheme)-\(themeName)"
    }
    private func toggleCanvasControls(_ point: CGPoint) -> Bool {
        guard !interaction.holdsAutoHide else { return false }
        guard page == .playing else { return false }
        if let window = NSApp.currentEvent?.window ?? NSApp.keyWindow, !window.styleMask.contains(.fullScreen), ResizeBoundary.contains(point, in: CGRect(origin: .zero, size: window.frame.size)) { return false }
        let actualWidth = NSApp.keyWindow?.contentView?.bounds.width ?? windowWidth
        if showQueue && barVisible && point.x > actualWidth - panelWidth(actualWidth, overlay: true) { return false }
        let reveal = !barVisible
        controlsOverride = reveal
        videoHideTask?.cancel()
        if reveal { showVideoControls() }
        return true
    }
    private func showVideoControls() {
        guard !interaction.holdsAutoHide else { videoHideTask?.cancel(); return }
        guard page == .playing, activePointerInside else { return }
        controlsOverride = nil
        videoControlsVisible = true
        videoHideTask?.cancel()
        videoHideTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled, page == .playing, activePointerInside, !interaction.holdsAutoHide else { return }
                controlsOverride = nil
                videoControlsVisible = false
            } catch { }
        }
    }
    private var playingEntry: some View {
        Button { selectTab(.playing) } label: {
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .symbolEffect(.variableColor.iterative, options: .repeating, isActive: player.isPlaying && !reduceMotion)
                    .layoutPriority(1)
                AdaptiveToolbarSongTitle(text: NowPlayingTabTitle.text(for: player.nowPlaying), active: barVisible,
                    color: page == .playing ? (playingScheme == .light ? .black : .white) : .labelColor)
                    .layoutPriority(-1)
            }
        }
        .modifier(ToolbarTabHighlight(selected: page == .playing, accent: effectiveAccent))
        .accessibilityLabel("正在播放：" + NowPlayingTabTitle.text(for: player.nowPlaying))
        .help(NowPlayingTabTitle.text(for: player.nowPlaying))
    }
    @ViewBuilder private var libraryToolbarControls: some View {
        if (page == .library || page == .favorites || page == .collections) && shows(.locate) {
            Button("定位当前播放", systemImage: "scope") {
                if page != .collections { mediaFilter = .all; search = ""; page = .library }
                DispatchQueue.main.async { NotificationCenter.default.post(name: .locateCurrentMedia, object: nil) }
            }.disabled(player.nowPlaying == nil).help("定位并选中当前播放的文件或视频")
        }
        if page == .collections && shows(.play) {
            CollectionToolbarControls(kind: .play)
        }
                    if page != .playing && page != .collections && shows(.play) {
                        Button("播放", systemImage: "play.fill") {
                            if let song = visibleSongs.first {
                                if page == .queue { player.playQueued(song) } else { player.playLibrary(song, in: visibleSongs) }
                            }
                        }
                        .disabled(visibleSongs.isEmpty)
                    }
    }
    @ViewBuilder private var playingDisplayControls: some View {
                    if page == .playing && shows(.lyrics) {
                        Button {
                            withAnimation(.smooth(duration: 0.3)) {
                                if player.isVideo { videoLyricsEnabled.toggle() }
                                else { splitView = false; showsLyrics.toggle() }
                            }
                        } label: {
                            Label("歌词", systemImage: (player.isVideo ? videoLyricsEnabled : showsLyrics) ? "text.bubble.fill" : "text.bubble")
                        }
                        .disabled(player.isVideo && player.lyrics.isEmpty)
                        .help(player.isVideo ? (player.lyrics.isEmpty ? "请先为视频匹配歌词或字幕" : "显示或隐藏视频下方歌词") : (showsLyrics ? "隐藏歌词，显示封面" : "显示歌词，隐藏封面"))
                    }
                    if page == .playing && shows(.split) {
                        Button { withAnimation(.smooth(duration: 0.3)) { splitView.toggle() } } label: {
                            Label("封面与歌词并排显示", systemImage: splitView ? "rectangle.split.2x1.fill" : "rectangle.split.2x1")
                        }
                        .disabled(player.isVideo)
                        .accessibilityValue(splitView ? "已开启" : "已关闭")
                        .help(splitView ? "退出封面与歌词并排显示" : "左侧封面，右侧歌词")
                    }
                    if (page == .playing || (showLibraryLyrics && !showQueue)) && shows(.artwork) {
                        Button { lyricsArtworkBackground.toggle() } label: {
                            Label("模糊封面作为背景", systemImage: lyricsArtworkBackground ? "photo.fill" : "photo")
                        }
                        .disabled(!hasArtwork)
                        .help(!hasArtwork ? "当前文件没有可用封面" : (lyricsArtworkBackground ? "恢复默认背景" : "模糊封面作为背景"))
                    }
    }
    @ViewBuilder private var lyricTimingControls: some View {
                    if page == .playing && shows(.lyricTiming) {
                        Button("歌词提前 0.2 秒", systemImage: "gobackward") { player.adjustLyrics(by: -0.2) }
                            .disabled(player.lyrics.isEmpty).help("歌词提前 0.2 秒（不改变文件进度）")
                        Button("歌词延后 0.2 秒", systemImage: "goforward") { player.adjustLyrics(by: 0.2) }
                            .disabled(player.lyrics.isEmpty).help("歌词延后 0.2 秒（不改变文件进度）")
                    }
    }
    @ViewBuilder private var menuLyricsControl: some View {
                    if shows(.menuLyrics) { Button {
                        showMenuBarLyrics.toggle()
                    } label: {
                        Label("菜单栏歌词", systemImage: showMenuBarLyrics ? "rectangle.topthird.inset.filled" : "menubar.rectangle")
                    }
                    .help(showMenuBarLyrics ? "隐藏菜单栏歌词" : "显示菜单栏歌词")
                    }
    }
    @ViewBuilder private var collectionToolbarControls: some View {
        if page == .collections {
            CollectionToolbarControls(kind: .management)
        }
                    if (page == .library || page == .favorites || page == nil) && shows(.filter) {
                        Menu {
                            Toggle("我喜欢", isOn: Binding(get: { page == .favorites }, set: { page = $0 ? .favorites : .library }))
                            Divider()
                            ForEach(MediaFilter.allCases) { filter in
                                Toggle(filter.rawValue, isOn: Binding(get: { mediaFilter == filter }, set: { if $0 { mediaFilter = filter } }))
                            }
                        } label: { ToolbarGlyph(symbol: "line.3.horizontal.decrease", title: "筛选") }
                            .help("筛选")
                           
                    }
        if page == .library || page == .favorites || page == nil {
            if libraryViewStyle == "covers" {
                Menu {
                    Toggle("A → Z", isOn: Binding(get: { coverSortAscending }, set: { if $0 { coverSortAscending = true } }))
                    Toggle("Z → A", isOn: Binding(get: { !coverSortAscending }, set: { if $0 { coverSortAscending = false } }))
                } label: { ToolbarGlyph(symbol: "arrow.up.arrow.down", title: "排序") }
                    .help("封面排序：字母及汉字拼音")
                    
            }
            Menu {
                Toggle("列表", isOn: Binding(get: { libraryViewStyle == "list" }, set: { if $0 { libraryViewStyle = "list" } }))
                Toggle("封面", isOn: Binding(get: { libraryViewStyle == "covers" }, set: { if $0 { libraryViewStyle = "covers" } }))
            } label: { ToolbarGlyph(symbol: libraryViewStyle == "covers" ? "square.grid.2x2" : "list.bullet", title: "视图") }
                .help("视图")
            if libraryViewStyle == "covers" {
                Menu {
                    ForEach(CoverGrouping.allCases) { kind in
                        Toggle(kind.title, isOn: Binding(get: { coverGroupingRaw == kind.rawValue }, set: { if $0 { coverGroupingRaw = kind.rawValue } }))
                    }
                } label: { ToolbarGlyph(symbol: (CoverGrouping(rawValue: coverGroupingRaw) ?? .album).icon, title: "分类") }
                    .help("分类")
            }
        }
    }
    @ViewBuilder private var displayToolbarControls: some View {
        if page == .playing { menuLyricsControl }
        playingDisplayControls
        if page != .playing {
            menuLyricsControl
                        if shows(.sideLyrics) { Button { withAnimation(.smooth(duration: 0.25)) { showLibraryLyrics.toggle() } } label: {
                            Label("侧边歌词", systemImage: "sidebar.right")
                        }.help(showLibraryLyrics ? "收起侧边歌词" : "展开侧边歌词")
                        }
        }
    }
    private var searchControl: some View {
        let expanded = searchExpanded
        return HStack(spacing: 6) {
            Button {
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { searchExpanded.toggle() }
            } label: { Image(systemName: "magnifyingglass").frame(minWidth: 20, minHeight: 22).contentShape(Rectangle()) }
                .accessibilityLabel(expanded ? "收起搜索" : "搜索")
            if expanded {
                TextField("文件、艺人或专辑", text: $search)
                    .textFieldStyle(.plain).focused($searchFocused)
                    .onSubmit { searchFocused = false }
                    .onExitCommand { withAnimation { searchExpanded = false }; searchFocused = false }
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).accessibilityLabel("清除搜索")
                }
                if windowWidth < 1100 {
                    Button { withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { searchExpanded = false }; searchFocused = false } label: { Image(systemName: "chevron.right") }
                        .buttonStyle(.plain).accessibilityLabel("收起搜索")
                }
            }
        }
        .frame(width: expanded ? (windowWidth >= 1100 ? 200 : 180) : 32)
        .contentShape(Rectangle())
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: expanded)
        .onChange(of: searchExpanded) { _, value in if value { searchFocused = true } }
    }

}

private struct NativeLibrary: View {
    @ObservedObject var scrollMemory: ScrollPositionMemory
    private var coverScrollKey: String { "covers:\(page.rawValue):\(coverGroupingRaw):\(coverGroupID ?? "root")" }
    @AppStorage("coverSortAscending") private var coverSortAscending = true
    @AppStorage("coverGrouping") private var coverGroupingRaw = "album"
    @State private var coverGroupID: String?
    @State private var portraitRevision = 0
    @StateObject private var coverCatalog = CoverCatalog()
    private var coverGroups: [MediaCoverGroup] { coverCatalog.groups }
    private var currentCoverGroup: MediaCoverGroup? {
        guard let coverGroupID else { return nil }
        return coverGroups.first { $0.id == coverGroupID }
    }
    private func publishCoverNavigation() {
        guard isActive else { return }
        let title = viewStyle == "covers" ? currentCoverGroup.map { "全部" + $0.kind.title } : nil
        NotificationCenter.default.post(name: Notification.Name("MyPlayer.coverNavigationChanged"), object: title)
    }
    private func refreshCoverCatalog() {
        guard isActive, viewStyle == "covers" else { coverCatalog.suspend(); return }
        coverCatalog.update(songs, grouping: CoverGrouping(rawValue: coverGroupingRaw) ?? .album, ascending: coverSortAscending)
    }
    private var coverSongs: [Song] { currentCoverGroup?.songs ?? songs }

    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var collectionStore: CollectionStore
    @State private var locateRequest: UUID?
    @State private var locateRow: Int?
    @State private var editingSong: Song?
    @State private var creatingCollection = false
    @State private var newCollectionName = ""
    @State private var collectionSongIDs: [UUID] = []
    let page: MusicPage
    let search: String
    let mediaFilter: MediaFilter
    let bottomClearance: CGFloat
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("libraryViewStyle") private var viewStyle = "list"
    @State private var gridScrolling = false
    @State private var selectionAnchor: Song.ID?
    @FocusState private var gridFocused: Bool
    @State private var selection = Set<Song.ID>()
    @State private var sortOrder: [KeyPathComparator<Song>] = []

    private var songs: [Song] {
        let source: [Song]
        switch page {
        case .queue: source = player.queuedSongs
        case .favorites: source = player.sortedLibrary.filter(\.isFavorite)
        default: source = player.sortedLibrary
        }
        if (page == .queue || mediaFilter == .all) && search.isEmpty { return source }
        let filtered = source.filter { (page == .queue || mediaFilter.includes($0)) && (search.isEmpty || "\($0.title) \($0.artist) \($0.album)".localizedStandardContains(search)) }
        return filtered
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
        GeometryReader { geometry in
            let displayed = songs
            VStack(alignment: .leading, spacing: 12) {
                if viewStyle == "covers" && page != .queue {
                    coverGrid
                } else {
                Table(of: Song.self, selection: $selection, sortOrder: $sortOrder) {
                    TableColumn(page == .queue ? "移除" : "添加") { song in
                        Button {
                            if page == .queue { player.confirmDequeue(song) } else { player.enqueue(song) }
                        } label: { Image(systemName: page == .queue ? "minus.circle" : "plus.circle") }
                            .buttonStyle(.borderless)
                            .help(page == .queue ? "从播放队列移除" : "添加到播放队列末尾")
                            .accessibilityLabel("\(page == .queue ? "从队列移除" : "添加到播放队列")：\(song.title)")
                    }.width(36)
                    TableColumn("文件", value: \.title) { song in
                        HStack(spacing: 8) {
                            Image(systemName: player.nowPlaying?.id == song.id ? "waveform" : song.isVideo ? "film" : "music.note")
                                .accessibilityHidden(true)
                                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: player.nowPlaying?.id == song.id && player.isPlaying && isActive && !reduceMotion)
                                .foregroundStyle(player.nowPlaying?.id == song.id ? Color.accentColor : Color.secondary)
                            ScrollingSongTitle(text: song.title, isActive: isActive)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }.width(min: 60, ideal: max(60, geometry.size.width * 0.42), max: .infinity)
                    TableColumn("喜欢") { song in
                        Button { player.confirmToggleFavorite(song) } label: {
                            Image(systemName: song.isFavorite ? "heart.fill" : "heart")
                                .foregroundStyle(song.isFavorite ? Color.accentColor : Color.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help(song.isFavorite ? "取消喜欢" : "喜欢")
                    }.width(42)
                    TableColumn("艺人", value: \.artist) { song in
                        ScrollingSongTitle(text: song.artist, isActive: isActive)
                    }.width(min: 36, ideal: max(36, geometry.size.width * 0.18), max: .infinity)
                    TableColumn("专辑", value: \.album) { song in
                        ScrollingSongTitle(text: song.album, isActive: isActive)
                    }.width(min: 36, ideal: max(36, geometry.size.width * 0.20), max: .infinity)
                    TableColumn("时长", value: \.duration) { song in Text(formatTime(song.duration)).monospacedDigit() }.width(60)
                } rows: {
                    ForEach(displayed) { song in
                        TableRow(song)
                    }
                }

                .scrollIndicators(.hidden, axes: .horizontal)
                .focusEffectDisabled()
                .animation(nil, value: displayed.map(\.id))
                .onChange(of: sortOrder) { _, value in
                    if page != .queue { player.sortLibrary(using: value) }
                }
                .focusedValue(\.libraryActions, isActive ? LibraryActions(
                    selectAll: { selection = Set(songs.map(\.id)) },
                    remove: removeSelection,
                    addToQueue: { for song in songs where selection.contains(song.id) { player.enqueue(song) } },
                    hasSelection: !selection.isEmpty) : nil)
                .onDeleteCommand { if isActive && ShortcutStore.shared.binding(.removeSelected) == ShortcutAction.removeSelected.standard { removeSelection() } }
                .scrollContentBackground(.hidden)
                .alternatingRowBackgrounds(.disabled)
                .background(TableTransparency(bottomInset: bottomClearance, selectionIDs: selection, locateRow: locateRow, locateRequest: locateRequest))
                .contextMenu(forSelectionType: Song.ID.self) { ids in
                    if let id = ids.first, let song = player.library.first(where: { $0.id == id }) {
                        MediaContextMenu(song: song, collectionIDs: selectedIDs(for: song), play: { play(song) }, edit: { editingSong = song }, createCollection: {
                            collectionSongIDs = selectedIDs(for: song); newCollectionName = ""; creatingCollection = true
                        }, removalTitle: page == .queue ? "从播放队列移除" : "从资料库移除", remove: {
                            if page == .queue { player.confirmDequeue(song) } else { player.confirmRemoveSong(song) }
                        })
                    }
                } primaryAction: { ids in
                    if let id = ids.first, let song = player.library.first(where: { $0.id == id }) { play(song) }
                }
                .overlay {
                    if songs.isEmpty {
                        ContentUnavailableView(search.isEmpty ? "暂无文件" : "没有找到文件", systemImage: page.icon,
                                               description: Text(search.isEmpty ? "通过“文件”菜单导入文件" : "尝试其他关键词"))
                    }
                }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .libraryHome)) { _ in
            guard isActive else { return }
            scrollMemory.resetToTop("covers:\(page.rawValue):\(coverGroupingRaw):root")
            coverGroupID = nil; selection.removeAll()
            if viewStyle != "covers", !songs.isEmpty { locateRow = 0; locateRequest = UUID() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .locateCurrentMedia)) { _ in
            guard isActive, let song = player.nowPlaying else { return }
            selection = [song.id]
            if viewStyle == "covers" { scrollMemory.suspend(); coverGroupID = coverGroups.first { $0.songs.contains(where: { $0.id == song.id }) }?.id }
            locateRow = songs.firstIndex { $0.id == song.id }
            locateRequest = UUID()
            if viewStyle == "covers" {
                scrollMemory.afterRestoration(of: coverScrollKey) {
                    guard isActive else { return }
                    withAnimation(.smooth(duration: 0.25)) { scrollProxy.scrollTo(song.id, anchor: .center) }
                }
            } else {
                DispatchQueue.main.async { withAnimation(.smooth(duration: 0.25)) { scrollProxy.scrollTo(song.id, anchor: .center) } }
            }
        }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            guard isActive, page != .queue else { return false }
            return FileDropImporter.receive(providers) { player.importDroppedMedia($0) }
        }
        .onAppear { refreshCoverCatalog(); publishCoverNavigation() }
        .onChange(of: coverGroupID) { _, _ in publishCoverNavigation() }
        .onChange(of: currentCoverGroup?.title) { _, _ in publishCoverNavigation() }
        .onChange(of: isActive) { _, _ in refreshCoverCatalog(); publishCoverNavigation() }
        .onChange(of: viewStyle) { _, _ in refreshCoverCatalog(); publishCoverNavigation() }
        .onChange(of: search) { _, _ in refreshCoverCatalog() }
        .onChange(of: mediaFilter) { _, _ in refreshCoverCatalog() }
        .onChange(of: coverGroupingRaw) { _, _ in refreshCoverCatalog() }
        .onChange(of: coverSortAscending) { _, _ in refreshCoverCatalog() }
        .onReceive(player.$library.dropFirst()) { _ in DispatchQueue.main.async { refreshCoverCatalog() } }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("MyPlayer.resetCoverBrowsing"))) { _ in scrollMemory.suspend(); coverGroupID = nil; selection.removeAll() }
        .sheet(item: $editingSong) { MediaInfoEditor(song: $0).environmentObject(player) }
        .onChange(of: creatingCollection) { _, presented in
            guard presented else { return }; creatingCollection = false
            CollectionNameDialog.present(title: "新建合集", saveTitle: "创建并添加", name: newCollectionName) { value in
                collectionStore.create(value, songs: collectionSongIDs)
            }
        }

    }
    private var coverGrid: some View {
        VStack(spacing: 0) {
            if let group = currentCoverGroup {
                VStack(alignment: .leading, spacing: 4) {
                    PageHeading(group.title)
                    Text("\(group.songs.count) 个文件").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 148, maximum: 180), spacing: 10)], alignment: .leading, spacing: 12) {
                if currentCoverGroup == nil {
                    ForEach(coverGroups) { group in
                        coverGroupCard(group)
                            .id(group.id)
                            .contentShape(Rectangle())
                            .onTapGesture { scrollMemory.suspend(); coverGroupID = group.id; selection.removeAll() }
                            .contextMenu {
                                if group.kind == .artist {
                                    Button("设置艺人照片…", systemImage: "photo") {
                                        ArtistPortraitStorage.choose(for: group.title) { portraitRevision += 1 }
                                    }
                                }
                                Button("播放全部", systemImage: "play.fill") {
                                    if let first = group.songs.first { player.playLibrary(first, in: group.songs) }
                                }
                            }
                    }
                } else {
                ForEach(Array(coverSongs.enumerated()), id: \.element.id) { index, song in
                    VStack(alignment: .leading, spacing: 7) {
                        NativeArtwork(song: song, maximum: 320, isActive: isActive).aspectRatio(1, contentMode: .fit).frame(maxWidth: .infinity)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: SurfaceCorners.cover))
                            .clipShape(RoundedRectangle(cornerRadius: SurfaceCorners.cover))
                            .padding(4)
                            .modifier(BetaGlassSurface(radius: SurfaceCorners.cover))
                            .overlay(alignment: .topTrailing) {
                                Button { player.enqueue(song) } label: { Image(systemName: "plus.circle.fill") }
                                    .buttonStyle(.borderless).padding(8).help("添加到播放队列末尾")
                            }
                        ScrollingSongTitle(text: song.title, height: 20, isActive: isActive && !gridScrolling)
                        Text(song.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .padding(6).id(song.id)
                    .background(selection.contains(song.id) ? Color.accentColor.opacity(0.2) : Color.clear, in: RoundedRectangle(cornerRadius: SurfaceCorners.cover))
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { play(song) }
                    .onTapGesture { selectCover(song); gridFocused = true }
                    .contextMenu {
                        MediaContextMenu(song: song, collectionIDs: selectedIDs(for: song), play: { play(song) }, edit: { editingSong = song }, createCollection: {
                            collectionSongIDs = selectedIDs(for: song); newCollectionName = ""; creatingCollection = true
                        }, removalTitle: "从资料库移除", remove: { player.confirmRemoveSong(song) })
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(song.displayName)
                }
                }
            }.padding(12).padding(.bottom, bottomClearance)
                .background(RetainedScrollPosition(memory: scrollMemory, key: coverScrollKey, active: isActive))
        }
        // Keep the scrolling viewport below the native toolbar and the group
        // heading. A separate blur overlay must not cover the first card rows.
        .scrollClipDisabled(false)
        .clipped()
        .onScrollPhaseChange { _, phase in gridScrolling = phase != .idle }
        .focusable().focused($gridFocused).focusEffectDisabled()
        .focusedValue(\.libraryActions, isActive ? LibraryActions(selectAll: { selection = Set(coverSongs.map(\.id)) }, remove: removeSelection, addToQueue: { for song in coverSongs where selection.contains(song.id) { player.enqueue(song) } }, hasSelection: !selection.isEmpty) : nil)
        .onDeleteCommand { if isActive && ShortcutStore.shared.binding(.removeSelected) == ShortcutAction.removeSelected.standard { removeSelection() } }
        }
        .clipped()
        .onChange(of: coverGroupingRaw) { _, _ in coverGroupID = nil; selection.removeAll() }
    }
    private func coverGroupCard(_ group: MediaCoverGroup) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack {
                if group.kind == .album {
                    NativeArtwork(song: group.representative, maximum: 320, isActive: isActive)
                } else if group.kind == .artist {
                    ArtistPortrait(name: group.title, revision: portraitRevision, active: isActive)
                } else {
                    Image(systemName: "folder.fill").resizable().scaledToFit().foregroundStyle(.yellow).padding(24)
                }
            }.aspectRatio(1, contentMode: .fit).frame(maxWidth: .infinity)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: SurfaceCorners.cover))
                .clipShape(RoundedRectangle(cornerRadius: SurfaceCorners.cover))
                .padding(4)
                .modifier(BetaGlassSurface(radius: SurfaceCorners.cover))
            ScrollingSongTitle(text: group.title, height: 20, isActive: isActive && !gridScrolling)
            Text("\(group.songs.count) 个文件").font(.caption).foregroundStyle(.secondary)
        }.padding(6)
    }
    private func selectedIDs(for song: Song) -> [UUID] {
        selection.contains(song.id) ? songs.filter { selection.contains($0.id) }.map(\.id) : [song.id]
    }
    private func selectCover(_ song: Song) {
        let flags = NSEvent.modifierFlags
        let displayed = viewStyle == "covers" ? coverSongs : songs
        if flags.contains(.shift), let anchor = selectionAnchor,
           let start = displayed.firstIndex(where: { $0.id == anchor }), let end = displayed.firstIndex(where: { $0.id == song.id }) {
            selection.formUnion(displayed[min(start, end)...max(start, end)].map(\.id))
        } else if flags.contains(.command) {
            if selection.contains(song.id) { selection.remove(song.id) } else { selection.insert(song.id) }
            selectionAnchor = song.id
        } else { selection = [song.id]; selectionAnchor = song.id }
    }
    private func removeSelection() {
        guard isActive else { return }
        let items = songs.filter { selection.contains($0.id) }
        guard !items.isEmpty else { return }
        let scope = page
        let ids = Set(items.map(\.id))
        let destination = scope == .queue ? "播放队列" : (scope == .favorites ? "我喜欢" : "资料库")
        RemovalConfirmation.request("移除选中的 \(items.count) 个项目？", message: "将从“\(destination)”移除这些项目，原文件会保留。") {
            for item in items {
                if scope == .queue { player.dequeue(item) }
                else if scope == .favorites {
                    if let latest = player.library.first(where: { $0.id == item.id }), latest.isFavorite { player.toggleFavorite(latest) }
                } else { player.removeSong(item) }
            }
            selection.subtract(ids)
        }
    }
    private func play(_ song: Song) {
        if page == .queue { player.playQueued(song) } else { player.playLibrary(song, in: viewStyle == "covers" ? coverSongs : songs) }
    }
}

func formatTime(_ value: TimeInterval) -> String {
    let seconds = value.isFinite ? Int(max(0, value)) : 0
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
}

struct LibraryActions {
    var selectAll: () -> Void
    var remove: () -> Void
    var addToQueue: () -> Void
    var hasSelection: Bool
}
private struct LibraryActionsKey: FocusedValueKey { typealias Value = LibraryActions }
extension FocusedValues {
    var libraryActions: LibraryActions? {
        get { self[LibraryActionsKey.self] }
        set { self[LibraryActionsKey.self] = newValue }
    }
}

private struct ToolbarControlVisibility: ViewModifier {
    let visible: Bool
    let reduceMotion: Bool
    func body(content: Content) -> some View {
        content.opacity(visible ? 1 : 0)
            .allowsHitTesting(visible)
            .accessibilityHidden(!visible)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: visible)
    }
}

extension Notification.Name { static let myPlayerNavigate = Notification.Name("MyPlayer.navigate") }
