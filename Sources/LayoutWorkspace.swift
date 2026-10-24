import SwiftUI
import Combine
import AVKit
import ImageIO

@MainActor private enum ArtworkThumbnailCache {
    static let images: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.totalCostLimit = 8 * 1024 * 1024
        cache.countLimit = 96
        return cache
    }()
}

struct NativeArtwork: View {
    let song: Song?
    var maximum = 96
    var isActive = true
    @State private var image: NSImage?
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFit() }
            else { Image(systemName: song?.isVideo == true ? "film" : "music.note").font(.system(size: 18)).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .task(id: isActive ? song?.artworkID : nil) {
            guard isActive, let data = song?.artworkData else { image = nil; return }
            if let cached = ArtworkThumbnailCache.images.object(forKey: "\(song?.artworkID ?? "none")-\(maximum)" as NSString) { image = cached; return }
            let thumbnail = await Task.detached(priority: .utility) {
                guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil as CGImage? }
                return CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: maximum, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary)
            }.value
            guard !Task.isCancelled, let thumbnail else { return }
            let decoded = NSImage(cgImage: thumbnail, size: NSSize(width: thumbnail.width, height: thumbnail.height))
            ArtworkThumbnailCache.images.setObject(decoded, forKey: "\(song?.artworkID ?? "none")-\(maximum)" as NSString, cost: thumbnail.bytesPerRow * thumbnail.height)
            image = decoded
        }
    }
}

struct NativeNowPlaying: View {
    @Environment(\.colorScheme) private var surfaceScheme
    @ObservedObject var player: PlayerManager
    let showsLyrics: Bool
    var splitView = false
    var isActive = true
    var hasArtwork = false
    var chromeVisible = true
    var coverTopClearance: CGFloat = 84
    var coverBottomClearance: CGFloat = 150
    @AppStorage("videoLyricsEnabled") private var videoLyricsEnabled = false
    @State private var editingSong: Song?
    @State private var videoLyricsHeight: CGFloat = 0
    @State private var videoPresentationSize: CGSize = .zero
    @AppStorage("lyricsArtworkBackground") private var artworkBackground = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let video = player.videoPlayer {
                GeometryReader { geometry in
                    let footerVisible = isActive && videoLyricsEnabled && !player.lyrics.isEmpty
                    let videoHeight = max(1, geometry.size.height - (footerVisible ? videoLyricsHeight * 2 : 0))
                    let aspect = videoPresentationSize.height > 0 ? videoPresentationSize.width / videoPresentationSize.height : 0
                    let pictureHeight = aspect > 0 ? min(videoHeight, geometry.size.width / aspect) : videoHeight
                    let pictureBottom = (geometry.size.height + pictureHeight) / 2
                    // Symmetric fitting keeps the picture center unchanged. Existing
                    // letterbox space is reused; the footer never overlays the picture.
                    ZStack(alignment: .bottom) {
                        NativeVideoView(player: video)
                            .frame(width: geometry.size.width, height: videoHeight)
                            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
                        if footerVisible {
                            VideoLyricsStrip(player: player, clock: player.clock, isActive: isActive)
                                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { videoLyricsHeight = $0 }
                                .position(x: geometry.size.width / 2, y: (pictureBottom + geometry.size.height) / 2)
                        }
                    }
                    .transaction { $0.animation = nil }
                }
                .onReceive(video.publisher(for: \.currentItem).map { item in
                    item?.publisher(for: \.presentationSize, options: [.initial, .new]).eraseToAnyPublisher()
                        ?? Just(CGSize.zero).eraseToAnyPublisher()
                }.switchToLatest().receive(on: DispatchQueue.main)) { videoPresentationSize = $0 }
                .background(Color.black).ignoresSafeArea()
            } else if !isActive {
                Color.clear
            } else if splitView {
                ZStack {
                    // One backdrop spans both columns; no separately cropped
                    // images or material boundaries at the center seam.
                    if hasArtwork && artworkBackground {
                        LyricsArtworkBackground(song: player.nowPlaying, isActive: isActive, dimming: surfaceScheme == .dark ? 0.3 : 0.02)
                    }
                    HStack(spacing: 0) {
                        FullArtwork(song: player.nowPlaying, isActive: isActive, showsBackdrop: false, topClearance: coverTopClearance, bottomClearance: coverBottomClearance, horizontalClearance: 24)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        NativeLyrics(player: player, clock: player.clock, isActive: isActive, followAnchor: 0.25, hidesPlayedLines: true, onDarkArtwork: artworkBackground && hasArtwork && surfaceScheme == .dark)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .transition(.opacity)
            } else if showsLyrics {
                ZStack {
                    if artworkBackground {
                        LyricsArtworkBackground(song: player.nowPlaying, isActive: isActive, dimming: surfaceScheme == .dark ? 0.3 : 0.02)
                    }
                    NativeLyrics(player: player, clock: player.clock, isActive: isActive, followAnchor: 0.25, horizontalInset: 48, hidesPlayedLines: true, onDarkArtwork: artworkBackground && hasArtwork && surfaceScheme == .dark)
                        .frame(maxWidth: 850)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .transition(.opacity)
            } else {
                FullArtwork(song: player.nowPlaying, isActive: isActive, showsBackdrop: artworkBackground, topClearance: coverTopClearance, bottomClearance: coverBottomClearance)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: showsLyrics)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: splitView)
        .contextMenu {
            if let song = player.nowPlaying {
                Section("播放控制") {
                    Button(player.isPlaying ? "暂停" : "播放", action: player.togglePlayPause)
                    Button("上一首", action: player.playPrevious)
                    Button("下一首") { player.playNext(manual: true) }
                }
                Section("收藏") { Button(song.isFavorite ? "取消喜欢" : "喜欢") { player.confirmToggleFavorite(song) } }
                Section("文件与信息") { MediaFileActions(song: song) { editingSong = song } }
            }
        }
        .sheet(item: $editingSong) { MediaInfoEditor(song: $0).environmentObject(player) }

    }
}

struct SideLyricsPanel: View {
    @ObservedObject var player: PlayerManager
    var isActive = true
    var body: some View {
        NativeLyrics(player: player, clock: player.clock, isActive: isActive, followAnchor: 1.0 / 3)
    }
}

struct NativeLyrics: View {
    @ObservedObject var player: PlayerManager
    let clock: PlaybackClock
    var isActive = true
    var followAnchor: CGFloat = 0.5
    var horizontalInset: CGFloat = 24
    var hidesPlayedLines = false
    var onDarkArtwork: Bool = false
    @AppStorage("lyricsBlurEnabled") private var lyricsBlur = false
    @AppStorage("lyricsFontSize") private var fontSize = 28.0
    @AppStorage("lyricsCentered") private var centered = true
    @AppStorage("lyricsFontName") private var fontName = "system"
    @AppStorage("lyricsFontWeight") private var fontWeight = "bold"
    @AppStorage("themeColorName") private var themeName = "system"
    @Environment(\.playbackAccent) private var playbackAccent
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index: Int? = 0
    @State private var manuallyScrolling = false
    @State private var following = true
    @State private var resumeTask: Task<Void, Never>?

    private var selectedWeight: Font.Weight { (LyricsWeight(rawValue: fontWeight) ?? .bold).weight }
    private var readableAccent: Color {
        let accent = playbackAccent ?? ThemeColor(rawValue: themeName)?.color ?? .accentColor
        return LyricContrast.color(accent, background: onDarkArtwork ? 0.32 : colorScheme == .dark ? 0.13 : 0.96)
    }
    var body: some View {
        let accent = readableAccent
        if player.lyrics.isEmpty {
            ContentUnavailableView("暂无歌词", systemImage: "text.quote")
        } else {
            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: centered ? .center : .leading, spacing: 26) {
                            ForEach(Array(player.lyrics.enumerated()), id: \.element.id) { position, line in
                                let distance = abs(position - (index ?? 0))
                                let current = position == index
                                let historyHidden = hidesPlayedLines && following && !manuallyScrolling && position < (index ?? 0)
                                Text(line.text)
                                    .font(fontName == "system" ? .system(size: fontSize, weight: selectedWeight) : .custom(fontName, size: fontSize).weight(selectedWeight))
                                    .foregroundStyle(current ? accent : (onDarkArtwork ? Color.white : Color.primary))
                                    .shadow(color: onDarkArtwork ? .black.opacity(0.6) : .clear, radius: 2)
                                    .opacity(historyHidden ? 0 : current ? 1 : distance <= 1 ? 0.60 : 0.42)
                                    .blur(radius: reduceMotion || manuallyScrolling || !lyricsBlur || current ? 0 : min(14, Double(distance) * 1.8))
                                    .scaleEffect(current ? 1 : 0.94, anchor: centered ? .center : .leading)
                                    .background(CanvasClickPassthrough(enabled: !historyHidden && isActive && !line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                                    .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
                                    .multilineTextAlignment(centered ? .center : .leading)
                                    .padding(.horizontal, horizontalInset)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        resumeTask?.cancel()
                                        manuallyScrolling = false
                                        following = true
                                        player.seek(to: line.time + (player.nowPlaying?.lyricsOffset ?? 0))
                                        if player.nowPlaying != nil && !player.isPlaying { player.togglePlayPause() }
                                    }
                                    .contextMenu {
                                        LyricLineContextMenu(time: line.time, following: $following, blur: $lyricsBlur, centered: $centered)
                                    }
                                    .allowsHitTesting(!historyHidden)
                                    .accessibilityHidden(historyHidden)
                                    .id(line.id)
                                    .animation(reduceMotion || manuallyScrolling ? nil : .smooth(duration: 0.55), value: index)
                                    .animation(reduceMotion || manuallyScrolling ? nil : .easeInOut(duration: 0.8), value: manuallyScrolling)
                            }
                        }
                        .padding(.top, geometry.size.height * followAnchor)
                        .padding(.bottom, geometry.size.height * (1 - followAnchor))
                    }
                    .scrollIndicators(.hidden)
                    .mask {
                        LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .white, location: 0.16),
                                               .init(color: .white, location: 0.84), .init(color: .clear, location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                    }
                    .onChange(of: index, initial: true) { _, value in
                        if following { scroll(value, proxy: proxy) }
                    }
                    .onChange(of: player.lyrics.first?.id) { _, _ in
                        resumeTask?.cancel()
                        manuallyScrolling = false
                        following = true
                        scroll(index ?? 0, proxy: proxy)
                    }
                    .onChange(of: following) { _, value in if value { scroll(index, proxy: proxy) } }
                    .onChange(of: followAnchor) { _, anchor in
                        if following, let index, player.lyrics.indices.contains(index) {
                            proxy.scrollTo(player.lyrics[index].id, anchor: UnitPoint(x: 0.5, y: anchor))
                        }
                    }
                    .onScrollPhaseChange { _, phase in
                        if phase == .interacting || phase == .decelerating {
                            resumeTask?.cancel()
                            manuallyScrolling = true
                            following = false
                        } else if phase == .idle && !following {
                            resumeTask?.cancel()
                            resumeTask = Task {
                                do {
                                    try await Task.sleep(for: .seconds(3))
                                    guard !Task.isCancelled else { return }
                                    manuallyScrolling = false
                                    try await Task.sleep(for: .seconds(0.8))
                                    guard !Task.isCancelled else { return }
                                    following = true
                                } catch { }
                            }
                        }
                    }
                }
            }
            .onReceive(LyricProgress.indices(times: clock.$time, lyrics: player.lyrics, offset: player.nowPlaying?.lyricsOffset ?? 0)) { value in
                if isActive && index != value { index = value }
            }
            .onChange(of: isActive) { _, active in
                if active { index = LRCParser.currentIndex(for: player.lyrics, at: clock.time - (player.nowPlaying?.lyricsOffset ?? 0)) ?? 0 }
            }
            .onChange(of: player.nowPlaying?.lyricsOffset) { _, offset in
                index = LRCParser.currentIndex(for: player.lyrics, at: clock.time - (offset ?? 0)) ?? (player.lyrics.isEmpty ? nil : 0)
            }
            .onChange(of: player.lyrics) { _, lines in
                index = LRCParser.currentIndex(for: lines, at: clock.time - (player.nowPlaying?.lyricsOffset ?? 0)) ?? (lines.isEmpty ? nil : 0)
            }
            .onDisappear { resumeTask?.cancel() }
        }
    }
    private func scroll(_ index: Int?, proxy: ScrollViewProxy) {
        guard let index, player.lyrics.indices.contains(index) else { return }
        let id = player.lyrics[index].id
        if reduceMotion { proxy.scrollTo(id, anchor: UnitPoint(x: 0.5, y: followAnchor)) }
        else { withAnimation(.smooth(duration: 0.7)) { proxy.scrollTo(id, anchor: UnitPoint(x: 0.5, y: followAnchor)) } }
    }
}

struct NativePlayerBar: View {
    @Environment(\.colorScheme) private var scheme
    @ObservedObject var player: PlayerManager
    var isActive = true
    let showPlaying: () -> Void
    var queueVisible = false
    var toggleQueue: () -> Void = {}
    var showThumbnail = false
    var compact = false
    var videoFullScreen = false
    @State private var showPlaybackModes = false
    @State private var videoMore = VideoMoreState()
    private var videoMoreExpanded: Bool { videoMore.isExpanded }
    @State private var videoControlsHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var videoPresentation = VideoPresentation.shared
    @Environment(\.playbackAccent) private var coverAccent
    private var playSymbolColor: Color {
        guard let rgb = NSColor(coverAccent ?? ThemeColor.current.color ?? .accentColor).usingColorSpace(.deviceRGB) else { return .white }
        return PlaybackButtonContrast.usesBlack(rgb.redComponent, rgb.greenComponent, rgb.blueComponent) ? .black : .white
    }
    var body: some View {
        Group {
            if compact {
                VStack(spacing: 6) {
                    titleAndPin.frame(maxWidth: .infinity, alignment: .leading)
                    if player.isVideo {
                        compactVideoControls
                    } else {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 10) { transport; Spacer(minLength: 8); accessories }
                            VStack(spacing: 6) { transport; accessories }
                        }
                    }
                    NativeTimeline(player: player, clock: player.clock, isActive: isActive)
                }
            } else {
        ViewThatFits(in: .horizontal) {
            VStack(spacing: 5) {
                HStack(spacing: 10) {
                    titleAndPin.frame(minWidth: 150, maxWidth: .infinity)
                    transport
                    accessories.frame(minWidth: 150, maxWidth: .infinity, alignment: .trailing)
                }
                NativeTimeline(player: player, clock: player.clock, isActive: isActive)
            }
            VStack(spacing: 5) {
                HStack(spacing: 6) { titleAndPin; accessories }
                transport.frame(maxWidth: .infinity)
                NativeTimeline(player: player, clock: player.clock, isActive: isActive)
            }
        }
            }
        }
        .controlSize(.regular)
        .padding(.horizontal, 16).padding(.vertical, 7)
        // ViewThatFits(horizontal) otherwise accepts the overlay's full height,
        // making the bar's mouse exclusion region cover the entire canvas.
        .fixedSize(horizontal: false, vertical: true)
        .modifier(PlayerBarSurface())
        .onHover { inside in
            guard compact && player.isVideo else { return }
            videoControlsHovered = inside
            if !inside { videoMore.leavePanel(popupOpen: showPlaybackModes) }
        }
    }
    private var compactVideoControls: some View {
        HStack(spacing: 5) {
            ZStack(alignment: .leading) {
                // The natural, collapsed transport always participates in layout.
                // Swap opacity rather than intrinsic sizes when expanding.
                transport.opacity(videoMoreExpanded ? 0 : 1)
                    .allowsHitTesting(!videoMoreExpanded).accessibilityHidden(videoMoreExpanded)
                accessories.opacity(videoMoreExpanded ? 1 : 0)
                    .allowsHitTesting(videoMoreExpanded).accessibilityHidden(!videoMoreExpanded)
            }
            Spacer(minLength: 0)
            Button {
                // A first click pins an already hover-open palette; the next
                // click closes it, even while the pointer remains over the button.
                videoMore.clickMore()
            } label: {
                Image(systemName: videoMoreExpanded ? "ellipsis.circle.fill" : "ellipsis")
                    .foregroundStyle(videoMoreExpanded ? playSymbolColor : inactiveSymbolColor)
                    .frame(width: 22, height: 22)
            }
            .modifier(PlaybackActivationStyle(active: videoMoreExpanded))
            .help("更多播放功能")
            .onHover { if $0 { videoMore.hoverMore() } }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: showPlaybackModes) { _, shown in
            if !shown { videoMore.popupClosed(pointerInside: videoControlsHovered) }
        }
        .onChange(of: isActive) { _, active in if !active { videoMore.hidePanel() } }
        .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: videoMoreExpanded)
    }
    private var titleAndPin: some View {
        HStack(spacing: 5) {
            Button(action: showPlaying) {
                HStack(spacing: 6) {
                    if showThumbnail {
                        NativeArtwork(song: player.nowPlaying, isActive: isActive)
                            .frame(width: 30, height: 30)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        ScrollingSongTitle(text: player.nowPlaying?.title ?? "未在播放", height: 20, isActive: isActive)
                        if let artist = player.nowPlaying?.artist.trimmingCharacters(in: .whitespacesAndNewlines), !artist.isEmpty {
                            Text(artist).font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }.buttonStyle(.plain).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private var transport: some View {
        HStack(spacing: 8) {
            Button(action: player.playPrevious) { Image(systemName: "backward.end.fill").foregroundStyle(inactiveSymbolColor).frame(width: 22, height: 22) }
                .modifier(PlaybackActivationStyle(active: false)).accessibilityLabel("上一首")
            Button(action: player.togglePlayPause) {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(player.isPlaying ? playSymbolColor : inactiveSymbolColor).frame(width: 28, height: 28)
            }
            .modifier(PlaybackActivationStyle(active: player.isPlaying))
            .accessibilityLabel(player.isPlaying ? "暂停" : "播放")
            Button { player.playNext(manual: true) } label: { Image(systemName: "forward.end.fill").foregroundStyle(inactiveSymbolColor).frame(width: 22, height: 22) }
                .modifier(PlaybackActivationStyle(active: false)).accessibilityLabel("下一首")
        }
    }
    private var inactiveSymbolColor: Color { scheme == .dark ? Color(white: 0.82) : Color(white: 0.28) }
    private var accessories: some View {
        HStack(spacing: 5) {
            Button {
                if let song = player.nowPlaying { player.confirmToggleFavorite(song) }
            } label: {
                Image(systemName: player.nowPlaying?.isFavorite == true ? "heart.fill" : "heart")
                    .symbolEffect(.bounce, options: .nonRepeating, value: !reduceMotion && player.nowPlaying?.isFavorite == true)
                    .foregroundStyle(player.nowPlaying?.isFavorite == true ? playSymbolColor : inactiveSymbolColor)
                    .frame(width: 22, height: 22)
            }
            .modifier(PlaybackActivationStyle(active: player.nowPlaying?.isFavorite == true))
            .disabled(player.nowPlaying == nil).accessibilityLabel("喜欢")
            Button { showPlaybackModes.toggle() } label: {
                Image(systemName: player.repeatMode.icon)
                    .foregroundStyle(player.repeatMode == .playOnce ? inactiveSymbolColor : playSymbolColor)
                    .frame(width: 22, height: 22)
            }
            .modifier(PlaybackActivationStyle(active: player.repeatMode != .playOnce))
            .popover(isPresented: $showPlaybackModes, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(RepeatMode.allCases) { mode in
                        Button {
                            player.repeatMode = mode
                            showPlaybackModes = false
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: player.repeatMode == mode ? "checkmark" : mode.icon).frame(width: 18)
                                Text(mode.label)
                                Spacer(minLength: 0)
                            }.padding(.horizontal, 10).padding(.vertical, 8).contentShape(Rectangle())
                        }.buttonStyle(.plain).foregroundStyle(.primary)
                    }
                }.padding(6).frame(width: 200)
            }
            .help("播放模式：\(player.repeatMode.label)").accessibilityLabel("播放模式")
            if player.isVideo {
                Button { VideoPresentation.shared.toggleFullScreen() } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").foregroundStyle(videoFullScreen ? playSymbolColor : inactiveSymbolColor).frame(width: 22, height: 22)
                }.modifier(PlaybackActivationStyle(active: videoFullScreen)).help("视频全屏 / 退出全屏").accessibilityLabel("视频全屏")
                Button { VideoPresentation.shared.togglePictureInPicture() } label: {
                    Image(systemName: "pip.enter").foregroundStyle(videoPresentation.isPictureInPicture ? playSymbolColor : inactiveSymbolColor).frame(width: 22, height: 22)
                }.modifier(PlaybackActivationStyle(active: videoPresentation.isPictureInPicture)).help("画中画 / 退出画中画").accessibilityLabel("画中画")
            }
        
            queueControl

        }
        .fixedSize()
    }
    @ViewBuilder private var queueControl: some View {
        queueButton.modifier(PlaybackActivationStyle(active: queueVisible))
    }
    private var queueButton: some View {
        Button(action: toggleQueue) {
            Image(systemName: "list.bullet").frame(width: 22, height: 22)
                .foregroundStyle(queueVisible ? playSymbolColor : inactiveSymbolColor)
        }
        .accessibilityLabel("播放队列").accessibilityValue(queueVisible ? "已展开" : "已收起")
        .help(queueVisible ? "收起播放队列" : "展开播放队列")
    }

}

struct NativeTimeline: View {
    @ObservedObject var player: PlayerManager
    let clock: PlaybackClock
    var isActive = true
    @Environment(\.playbackAccent) private var playbackAccent
    @State private var displayedTime: TimeInterval = 0
    @State private var dragging = false
    @State private var draft = 0.0
    var body: some View {
        HStack {
            Text(formatTime(dragging ? draft : displayedTime)).monospacedDigit().frame(width: 42)
            AccentProgressSlider(value: Binding(get: { dragging ? draft : displayedTime }, set: { draft = $0 }), range: 0...max(1, player.duration), accent: playbackAccent ?? ThemeColor.current.color ?? .accentColor, enabled: player.nowPlaying != nil) { editing in
                if editing { draft = displayedTime; dragging = true }
                else { dragging = false; player.seek(to: draft) }
            }
            .frame(minWidth: 40, maxWidth: .infinity)
            .disabled(player.nowPlaying == nil)
            .accessibilityLabel("播放进度")
            Text(formatTime(player.duration)).monospacedDigit().frame(width: 42)
        }.font(.caption)
        .onReceive(clock.$time) { value in if isActive { displayedTime = value } }
        .onChange(of: isActive, initial: true) { _, active in if active { displayedTime = clock.time } }
    }
}

struct FullArtwork: View {
    let song: Song?
    var isActive = true
    var showsBackdrop = false
    var topClearance: CGFloat = 84
    var bottomClearance: CGFloat = 150
    var horizontalClearance: CGFloat = 40
    @Environment(\.colorScheme) private var scheme
    @State private var image: NSImage?
    var body: some View {
        GeometryReader { geometry in
            let placement = CoverCardLayout.placement(in: geometry.size, image: image?.size ?? CGSize(width: 1, height: 1), top: topClearance, bottom: bottomClearance, horizontal: horizontalClearance)
            ZStack(alignment: .topLeading) {
                if showsBackdrop {
                    LyricsArtworkBackground(song: song, isActive: isActive, dimming: scheme == .dark ? 0.3 : 0.02)
                }
                Group {
                    if let image {
                        Image(nsImage: image).resizable().scaledToFit()
                    } else {
                        Image(systemName: "music.note").font(.system(size: 80)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(width: max(0, placement.frame.width - placement.border * 2), height: max(0, placement.frame.height - placement.border * 2))
                .clipShape(.rect(cornerRadius: SurfaceCorners.cover))
                .padding(placement.border)
                .background(.regularMaterial, in: .rect(cornerRadius: SurfaceCorners.panel))
                .overlay(RoundedRectangle(cornerRadius: SurfaceCorners.cover).strokeBorder(.white.opacity(0.18), lineWidth: 1))
                .shadow(color: .black.opacity(scheme == .dark ? 0.25 : 0.12), radius: 18, y: 8)
                .contentTransition(.opacity)
                .modifier(BetaArtworkDepth())
                .position(x: placement.frame.midX, y: placement.frame.midY)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .task(id: isActive ? song?.artworkID : nil) {
            guard isActive, let data = song?.artworkData else { image = nil; return }
            let rendered = await Task.detached(priority: .utility) { ArtworkRendering.thumbnail(data, maximum: 1536) }.value
            guard !Task.isCancelled else { return }
            image = rendered.map(ArtworkRendering.native)
        }
    }
}

struct LyricsArtworkBackground: View {
    let song: Song?
    var isActive = true
    var dimming: Double = 0.68
    @State private var image: NSImage?
    @Environment(\.ambientArtworkColors) private var colors
    @EnvironmentObject private var player: PlayerManager
    @AppStorage("betaVisualStyle") private var style = "aurora"
    var body: some View {
        GeometryReader { geometry in
            if style != "off" && !colors.isEmpty {
                BetaAmbientLight(colors: colors, playing: isActive && player.isPlaying, immersive: true)
                    .background(colors.first ?? .clear)
                    .overlay(.black.opacity(dimming))
            } else if let image {
                Image(nsImage: image).resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .overlay(.black.opacity(dimming))
                    .clipped()
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: isActive ? song?.artworkID : nil) {
            guard isActive, let data = song?.artworkData else { image = nil; return }
            let rendered = await Task.detached(priority: .utility) { ArtworkRendering.backdrop(data) }.value
            guard !Task.isCancelled else { return }
            image = rendered.map(ArtworkRendering.native)
        }
    }
}

struct PlayerBarSurface: ViewModifier {
    func body(content: Content) -> some View {
        content.modifier(BetaGlassSurface(clear: true))
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }
}
