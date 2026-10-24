import Foundation
import AVFoundation
import MediaPlayer
import AppKit

// MARK: - 播放模式


/// High-frequency progress updates must not invalidate the library and its sort.
@MainActor
final class PlaybackClock: ObservableObject {
    @Published var time: TimeInterval = 0
}

// MARK: - 播放管理器

@MainActor
final class PlayerManager: NSObject, ObservableObject {

    private let userData: UserDataStore
    private var libraryByIDCache: [UUID: Song]?
    private var sortedCache: [Song]?
    @Published private(set) var library: [Song] = [] { didSet { sortedCache = nil; libraryByIDCache = nil } }
    @Published private(set) var nowPlaying: Song?
    @Published private(set) var isPlaying = false
    let clock = PlaybackClock()
    private(set) var currentTime: TimeInterval {
        get { clock.time }
        set { clock.time = newValue }
    }
    @Published var lyrics: [LyricLine] = []

    /// 播放列表（下一首队列），按加入顺序播放
    @Published private(set) var upNext: [UUID] = [] {
        didSet { if !loadingUserData { UserDataFiles.save(upNext, to: userData.file("queue.json")) } }
    }
    private var loadingUserData = true
    private var userDataGeneration = 0
    private var userDataObserver: NSObjectProtocol?
    /// 在线匹配文件信息的进度提示
    struct ActivityMessage: Equatable {
        let id = UUID()
        let text: String
    }
    @Published private(set) var matchActivity: ActivityMessage?
    @Published var repeatMode: RepeatMode = .repeatAll {
        didSet { userData.defaults.set(repeatMode.rawValue, forKey: "repeatMode") }
    }
    @Published private(set) var usesCustomLibraryOrder = false
    @Published var sortKey: SortKey = .title {
        didSet { sortedCache = nil; userData.defaults.set(sortKey.rawValue, forKey: "sortKey") }
    }
    @Published var sortAscending: Bool = true {
        didSet { sortedCache = nil; userData.defaults.set(sortAscending, forKey: "sortAscending") }
    }

    var queuedSongs: [Song] { songs(for: upNext) }
    func songs(for ids: [UUID]) -> [Song] {
        if libraryByIDCache == nil { libraryByIDCache = Dictionary(uniqueKeysWithValues: library.map { ($0.id, $0) }) }
        return ids.compactMap { libraryByIDCache?[$0] }
    }
    @Published private(set) var libraryActivity: String?
    @Published var libraryImportMessage: String?
    @Published private(set) var watchedFolders: [WatchedMediaFolder] = []
    @Published private(set) var isScanningFolders = false
    @Published var autoScanFolders = true {
        didSet {
            guard scanConfigurationLoaded else { return }
            userData.defaults.set(autoScanFolders, forKey: "autoScanFolders")
            if autoScanFolders { scanFolders(manual: false) }
        }
    }
    private var scanCatalog = FolderScanCatalog()
    private let scanPersistence = LibraryPersistence()
    private var scanConfigurationLoaded = false
    private var folderScanTimer: Timer?
    private var folderActivationObserver: NSObjectProtocol?
    private var lastAutomaticScan = Date.distantPast
    private var scanQueued = false
    private enum MediaRequest {
        case importing([URL], folders: Bool)
        case scanning(manual: Bool)
    }
    private var mediaRequests: [MediaRequest] = []
    private var mediaWork: Task<Void, Never>?
    private var sessionPlaybackIDs: [UUID]?
    func playCollection(_ songs: [Song], startingAt id: UUID? = nil) {
        guard !songs.isEmpty else { return }
        let index = id.flatMap { id in songs.firstIndex { $0.id == id } } ?? 0
        sessionPlaybackIDs = songs.map(\.id)
        upNext = Array(songs.dropFirst(index + 1)).map(\.id)
        play(songs[index])
    }
    func playLibrary(_ song: Song, in source: [Song]? = nil) {
        let ordered = source ?? sortedLibrary
        let index = ordered.firstIndex { $0.id == song.id } ?? 0
        sessionPlaybackIDs = ordered.map(\.id)
        upNext = Array(ordered.dropFirst(index + 1)).map(\.id)
        play(song)
    }
    func removeFromQueue(_ song: Song) {
        sessionPlaybackIDs?.removeAll { $0 == song.id }
        dequeue(song)
        if nowPlaying?.id == song.id {
            if let next = queuedSongs.first { playQueued(next) }
            else { stop() }
        }
    }

    /// 当前高亮的歌词行索引
    var currentLineIndex: Int? {
        LRCParser.currentIndex(for: lyrics, at: currentTime - (nowPlaying?.lyricsOffset ?? 0))
    }

    var duration: TimeInterval { nowPlaying?.duration ?? 0 }

    /// 排序后的资料库（中文按拼音首字母 A→Z）
    var sortedLibrary: [Song] {
        if usesCustomLibraryOrder { return library }
        if let sortedCache { return sortedCache }
        let result = library.sorted { a, b in
            let result: ComparisonResult
            switch sortKey {
            case .title:
                result = pinyinCompare(a.title, b.title)
            case .artist:
                result = pinyinCompare(a.artist, b.artist)
            case .album:
                result = pinyinCompare(a.album, b.album)
            case .playCount:
                result = a.playCount == b.playCount
                    ? .orderedSame
                    : (a.playCount < b.playCount ? .orderedAscending : .orderedDescending)
            }
            return sortAscending ? result == .orderedAscending : result == .orderedDescending
        }
        sortedCache = result
        return result
    }

    /// 播放列表中下一首的歌名
    var upNextTitle: String? {
        guard let id = upNext.first,
              let song = library.first(where: { $0.id == id }) else { return nil }
        return song.title
    }

    /// 视频播放引擎（mp4/m4v/mov 走 AVPlayer）
    private(set) var mediaPlayer: AVPlayer?
    private var videoTimeObserver: Any?
    private var videoRateObserver: NSKeyValueObservation?
    private var videoStatusObserver: NSKeyValueObservation?
    @Published var playbackError: String?
    private var videoEndObserver: NSObjectProtocol?
    private var timer: Timer?
    private var userPaused = false
    /// 本次播放是否已计入播放次数（播过 1/3 时长计一次）
    private var countedThisPlay = false
    private var lastElapsedReport: TimeInterval = -1

    private var restoringSession: PlaybackSession?
    private var lastCheckpoint = Date.distantPast
    private var lastSavedSong: Song?

    /// 当前播放的是否为视频
    var videoPlayer: AVPlayer? { nowPlaying?.isVideo == true ? mediaPlayer : nil }
    var isVideo: Bool { nowPlaying?.isVideo == true && mediaPlayer != nil }

    override convenience init() { self.init(userData: .shared) }

    init(userData: UserDataStore, startsServices: Bool = true) {
        self.userData = userData
        super.init()
        userData.prepare()
        let d = userData.defaults
        repeatMode = RepeatMode(rawValue: d.string(forKey: "repeatMode") ?? "") ?? .repeatAll
        sortKey = SortKey(rawValue: d.string(forKey: "sortKey") ?? "") ?? .title
        sortAscending = d.object(forKey: "sortAscending") as? Bool ?? true
        usesCustomLibraryOrder = d.bool(forKey: "usesCustomLibraryOrder")
        loadLibrary()
        if startsServices { initializeFolderScanning() }
        scanForNewLyrics()
        if startsServices { setupRemoteCommands() }
        reloadQueue()
        loadingUserData = false
        restorePlaybackSession()
        userDataObserver = NotificationCenter.default.addObserver(forName: .myPlayerDataChanged, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated { self?.reloadUserData(note.object as? Set<String> ?? []) }
        }
    }

    /// 启动时扫描各文件来源文件夹，绑定新增的 .lrc 歌词文件
    private func scanForNewLyrics() {
        var changed = false
        for song in library where song.lyricsPath == nil && !song.lyricsDisabled {
            if let lrc = song.autoTimedTextURL {
                if let idx = library.firstIndex(where: { $0.id == song.id }) {
                    library[idx].lyricsPath = lrc.path
                    changed = true
                }
            }
        }
        if changed {
            saveLibrary()
        }
    }

    /// 中文按拼音首字母排序（zh 语言环境 + forcedOrdering）
    private func pinyinCompare(_ a: String, _ b: String) -> ComparisonResult {
        switch (a.isEmpty, b.isEmpty) {
        case (true, true): return .orderedSame
        case (true, false): return .orderedAscending
        case (false, true): return .orderedDescending
        default: break
        }
        return a.compare(b,
                         options: [.forcedOrdering, .caseInsensitive],
                         range: nil,
                         locale: Locale(identifier: "zh_Hans_CN"))
    }

    // MARK: 资料库管理

    func importAudioFiles() {
        FileImporter.pickAudioFiles { [weak self] urls in self?.enqueueMedia(.importing(urls, folders: false)) }
    }

    func importAudioFolder() {
        FileImporter.pickAudioFolder { [weak self] urls in self?.enqueueMedia(.importing(urls, folders: true)) }
    }

    @discardableResult
    func addFiles(at urls: [URL]) -> Int {
        var added: [Song] = []
        for url in urls {
            guard !library.contains(where: { $0.path == url.path }) else { continue }
            if let song = Song.load(at: url) {
                library.append(song)
                added.append(song)
            }
        }
        if !added.isEmpty {
            saveLibrary()
            startMetadataMatching(for: added)
        }
        return added.count
    }

    /// 拖拽导入：音乐文件加入资料库，lrc 按文件名自动匹配绑定
    @discardableResult
    func handleDropped(_ urls: [URL]) -> String? {
        let files = FileImporter.expandDroppedURLs(urls)
        let audio = files.filter { FileImporter.supportedExtensions.contains($0.pathExtension.lowercased()) }
        let lrcs = files.filter { $0.pathExtension.lowercased() == "lrc" }
        var messages: [String] = []

        if !audio.isEmpty {
            let added = addFiles(at: audio)
            let existing = audio.filter { url in library.contains { $0.path == url.path } }.count - added
            if added > 0 { messages.append("已导入 \(added) 个媒体文件") }
            if existing > 0 { messages.append("\(existing) 个文件已在资料库中，无需重复导入") }
            if added + existing < audio.count { messages.append("\(audio.count - added - existing) 个文件无法读取") }
        }

        var bound = 0
        var unmatched = 0
        for lrc in lrcs {
            guard let content = TextFileReader.read(lrc), !TimedTextParser.parse(content).isEmpty,
                  let song = LyricsMatcher.match(url: lrc, content: content, songs: library) else { unmatched += 1; continue }
            bindLyrics(lrc, to: song)
            bound += 1
        }
        if unmatched > 0 { messages.append("\(unmatched) 个歌词文件无法唯一匹配或没有有效时间轴，请右键文件手动选择") }
        if bound > 0 {
            messages.append("已为 \(bound) 个文件绑定歌词")
            // 若当前播放的文件刚好匹配到新歌词，立即刷新
            if let np = nowPlaying, lrcs.contains(where: { $0.path == np.lyricsPath }) {
                loadLyrics(for: np)
            }
        }
        return messages.isEmpty ? (lrcs.isEmpty ? "未发现支持的音频或视频文件" : "未找到与歌词同名的资料库项目；可先导入媒体文件") : messages.joined(separator: "；")
    }

    func removeSong(_ song: Song) {
        scanCatalog.exclude(song.url)
        saveScanCatalog()
        library.removeAll { $0.id == song.id }
        upNext.removeAll { $0 == song.id }
        if nowPlaying?.id == song.id {
            stop()
        }
        saveLibrary()
    }

    // MARK: Saved folder sources and background import

    private var scanCatalogURL: URL { libraryURL.deletingLastPathComponent().appendingPathComponent("folder-scan.json") }
    private func saveScanCatalog() {
        watchedFolders = scanCatalog.folders
        scanPersistence.save(scanCatalog, to: scanCatalogURL)
    }
    private func initializeFolderScanning() {
        autoScanFolders = userData.defaults.object(forKey: "autoScanFolders") as? Bool ?? true
        if let data = try? Data(contentsOf: scanCatalogURL), let saved = try? JSONDecoder().decode(FolderScanCatalog.self, from: data) {
            scanCatalog = saved
            UserDataFiles.accept(scanCatalogURL)
        } else if FileManager.default.fileExists(atPath: scanCatalogURL.path) {
            userData.report("folder-scan.json 无法读取，已停止自动扫描以保留原排除名单。")
            return
        } else {
            // Older versions did not save selected roots or removal history.
            // Recover known parent folders, then baseline their existing files
            // so previously removed files cannot silently return.
            for folder in Set(library.map { $0.url.deletingLastPathComponent() }) { scanCatalog.watch(folder) }
            scanCatalog.hasBaseline = library.isEmpty
        }
        watchedFolders = scanCatalog.folders
        scanConfigurationLoaded = true
        saveScanCatalog()
        if autoScanFolders { scanFolders(manual: false) }
        folderScanTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { if self?.autoScanFolders == true { self?.scanFolders(manual: false) } }
        }
        folderActivationObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if self?.autoScanFolders == true { self?.scanFolders(manual: false) } }
        }
    }
    func stopFolderScanning() {
        folderScanTimer?.invalidate()
        if let folderActivationObserver { NotificationCenter.default.removeObserver(folderActivationObserver) }
        folderActivationObserver = nil
    }
    func scanFolders(manual: Bool = true) {
        guard !scanQueued else { return }
        if !manual && Date().timeIntervalSince(lastAutomaticScan) < 30 { return }
        guard !scanCatalog.folders.isEmpty else {
            if manual { libraryImportMessage = "尚未添加扫描文件夹，请先使用“文件 → 导入文件夹”。" }
            return
        }
        scanQueued = true
        isScanningFolders = true
        enqueueMedia(.scanning(manual: manual))
    }
    func stopWatchingFolder(_ folder: WatchedMediaFolder) {
        scanCatalog.folders.removeAll { $0.path == folder.path }
        saveScanCatalog()
    }
    private func enqueueMedia(_ request: MediaRequest) {
        mediaRequests.append(request)
        guard mediaWork == nil else { return }
        mediaWork = Task { [weak self] in
            guard let self else { return }
            while !self.mediaRequests.isEmpty {
                let request = self.mediaRequests.removeFirst()
                await self.performMedia(request)
            }
            self.libraryActivity = nil
            self.mediaWork = nil
        }
    }
    private func performMedia(_ request: MediaRequest) async {
        let urls: [URL]
        let baselineOnly: Bool
        let announce: Bool
        let scanning: Bool
        switch request {
        case let .importing(selected, folders):
            urls = selected; announce = true; scanning = false; baselineOnly = false
            if folders { for folder in selected { scanCatalog.watch(folder) } }
            else { for file in selected { scanCatalog.allowExplicitFile(file) } }
            saveScanCatalog()
            libraryActivity = folders ? "正在导入文件夹…" : "正在导入媒体文件…"
        case let .scanning(manual):
            if !manual && !autoScanFolders {
                scanQueued = false; isScanningFolders = false
                return
            }
            urls = scanCatalog.folders.map(\.url)
            announce = manual; scanning = true; baselineOnly = !scanCatalog.hasBaseline
            lastAutomaticScan = Date()
            libraryActivity = baselineOnly ? "正在建立文件夹扫描记录…" : "正在扫描已添加的文件夹…"
        }
        let dataGeneration = userDataGeneration
        let existing = Set(library.map { FolderScanCatalog.key($0.url) })
        let excluded = scanCatalog.excludedPaths
        let report = await Task.detached(priority: .utility) {
            MediaImportWorker.read(urls: urls, existing: existing, excluded: excluded, baselineOnly: baselineOnly)
        }.value
        guard dataGeneration == userDataGeneration else {
            if scanning { scanQueued = false; isScanningFolders = false }
            libraryActivity = nil
            return
        }
        if baselineOnly {
            scanCatalog.establishBaseline(discovered: report.discovered, existing: existing)
            // An offline source has not been baselined yet. Retry it later rather
            // than accidentally resurrecting its previously removed files.
            if !report.unreadable.isEmpty { scanCatalog.hasBaseline = false }
            saveScanCatalog()
        }
        // Recheck on the main actor: removals/edits can happen during decoding.
        var currentPaths = Set(library.map { FolderScanCatalog.key($0.url) })
        let added = report.songs.filter { song in
            let path = FolderScanCatalog.key(song.url)
            return !scanCatalog.excludedPaths.contains(path) && currentPaths.insert(path).inserted
        }
        if !added.isEmpty {
            library.append(contentsOf: added)
            saveLibrary()
            startMetadataMatching(for: added)
        }
        if scanning {
            scanQueued = false
            isScanningFolders = false
            scanForNewLyrics()
        }
        if announce {
            var details = ["已添加 \(added.count) 个媒体文件"]
            if report.existing > 0 { details.append("\(report.existing) 个已在资料库中") }
            if report.excluded > 0 { details.append("\(report.excluded) 个已移除文件已跳过") }
            if report.failed > 0 { details.append("\(report.failed) 个文件无法读取或解码") }
            if !report.unreadable.isEmpty { details.append("无法访问：" + report.unreadable.prefix(5).joined(separator: "、")) }
            if report.discovered.isEmpty && report.unreadable.isEmpty { details.append("未发现支持的音频或视频文件") }
            if baselineOnly {
                details.append(report.unreadable.isEmpty
                    ? "旧版扫描记录已初始化，首次扫描保留现有资料库；以后新增文件将自动导入。需要补回旧文件时，请直接导入该文件。"
                    : "扫描基线尚未完整建立，请恢复不可访问的文件夹后重新扫描。")
            }
            libraryImportMessage = details.joined(separator: "；")
        }
    }

    // MARK: 收藏 / 播放次数

    func toggleFavorite(_ song: Song) {
        updateSong(song) { $0.isFavorite.toggle() }
    }

    private func incrementPlayCount(_ song: Song) {
        updateSong(song) { $0.playCount += 1 }
    }

    /// 就地修改资料库中的文件并持久化；若是当前文件则同步 nowPlaying
    private func updateSong(_ song: Song, _ transform: (inout Song) -> Void) {
        guard let idx = library.firstIndex(where: { $0.id == song.id }) else { return }
        transform(&library[idx])
        if nowPlaying?.id == song.id {
            nowPlaying = library[idx]
        }
        saveLibrary()
    }

    func editMetadata(_ song: Song, title: String, artist: String, album: String, artwork: Data?) {
        updateSong(song) {
            $0.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            $0.artist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
            $0.album = album.trimmingCharacters(in: .whitespacesAndNewlines)
            $0.artworkData = artwork
        }
        if nowPlaying?.id == song.id { updateNowPlayingInfo(force: true) }
    }

    // MARK: 播放列表（下一首）

    func sortLibrary(using comparators: [KeyPathComparator<Song>]) {
        guard !comparators.isEmpty else { return }
        let ordered = StableMediaOrder.sorted(library, using: comparators, identity: { $0.id.uuidString })
        guard !usesCustomLibraryOrder || ordered.map(\.id) != library.map(\.id) else { return }
        library = ordered
        usesCustomLibraryOrder = true
        userData.defaults.set(true, forKey: "usesCustomLibraryOrder")
        saveLibrary()
    }

    func enqueue(_ song: Song) {
        guard !upNext.contains(song.id) else { return }
        upNext.append(song.id)
        if sessionPlaybackIDs != nil && !sessionPlaybackIDs!.contains(song.id) { sessionPlaybackIDs?.append(song.id) }
    }

    func queueNext(_ song: Song) {
        guard !upNext.contains(song.id) else { return }
        // 当前空闲时直接播放待播文件；否则加入队尾
        if nowPlaying == nil {
            play(song)
            return
        }
        upNext.append(song.id)
    }

    func dequeue(_ song: Song) {
        if nowPlaying?.id != song.id { sessionPlaybackIDs?.removeAll { $0 == song.id } }
        upNext.removeAll { $0 == song.id }
    }

    func clearQueue() {
        sessionPlaybackIDs = nowPlaying.map { [$0.id] } ?? []
        upNext.removeAll()
    }

    /// 直接播放队列中的某首（并从队列移除）
    func playQueued(_ song: Song) {
        upNext.removeAll { $0 == song.id }
        play(song)
    }

    func adjustLyrics(by seconds: Double) {
        guard let song = nowPlaying else { return }
        updateSong(song) { $0.lyricsOffset = (($0.lyricsOffset + seconds) * 5).rounded() / 5 }
    }
    func resetLyricsOffset() {
        guard let song = nowPlaying else { return }
        updateSong(song) { $0.lyricsOffset = 0 }
    }

    // MARK: 歌词

    func importLyrics() {
        guard let song = nowPlaying else { return }
        chooseLyrics(for: song)
    }

    func chooseLyrics(for song: Song) {
        guard let url = FileImporter.pickLyricsFile() else { return }
        guard let content = TextFileReader.read(url), !TimedTextParser.parse(content).isEmpty else {
            playbackError = "所选文件没有可读取的 LRC、SRT 或 VTT 时间轴。"
            return
        }
        bindLyrics(url, to: song)
    }

    private func bindLyrics(_ url: URL, to song: Song) {
        let destination = userData.file("Lyrics").appendingPathComponent(song.id.uuidString + "." + url.pathExtension.lowercased())
        do {
            if url.standardizedFileURL != destination.standardizedFileURL { try Data(contentsOf: url).write(to: destination, options: .atomic) }
        } catch { playbackError = "无法保存歌词副本：\(error.localizedDescription)"; return }
        updateSong(song) { $0.lyricsPath = destination.path; $0.lyricsDisabled = false }
        if let current = nowPlaying, current.id == song.id { loadLyrics(for: current) }
    }

    func unmatchLyrics(for song: Song) {
        updateSong(song) { $0.lyricsPath = nil; $0.lyricsDisabled = true }
        if nowPlaying?.id == song.id { lyrics = [] }
    }

    private func loadLyrics(for song: Song) {
        guard !song.lyricsDisabled else { userData.watchLyrics(nil); lyrics = []; return }
        let candidate: URL?
        if let lp = song.lyricsPath {
            candidate = URL(fileURLWithPath: lp)
        } else {
            candidate = song.autoTimedTextURL
        }
        userData.watchLyrics(candidate)
        guard let lrc = candidate, let text = TextFileReader.read(lrc) else {
            lyrics = []
            return
        }
        lyrics = TimedTextParser.parse(text)
    }

    // MARK: 播放控制

    func play(_ song: Song) {
        restoringSession = nil
        startPlayback(song)
    }

    private func startPlayback(_ song: Song) {
        guard FileManager.default.fileExists(atPath: song.url.path) else {
            playbackError = "找不到媒体文件：\(song.url.lastPathComponent)"
            restoringSession = nil
            return
        }
        if song.isVideo {
            playVideo(song)
        } else {
            playAudio(song)
        }
    }

    private func playAudio(_ song: Song) { playVideo(song) }

    private func playVideo(_ song: Song) {
        timer?.invalidate()
        timer = nil
        teardownVideoEngine()

        let item = AVPlayerItem(url: song.url)
        item.preferredForwardBufferDuration = 3
        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = false
        mediaPlayer = player
        if let item = player.currentItem {
            videoStatusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                guard item.status == .failed else { return }
                let message = item.error?.localizedDescription ?? "无法读取这个视频文件。"
                Task { @MainActor [weak self] in
                    guard let self, self.mediaPlayer?.currentItem === item else { return }
                    self.playbackError = message
                    self.stop(preserveSession: true)
                }
            }
        }
        videoRateObserver = player.observe(\.rate, options: [.new]) { [weak self] observed, _ in
            let playing = observed.rate != 0
            Task { @MainActor [weak self] in
                guard let self, self.mediaPlayer === observed, self.restoringSession == nil else { return }
                if self.isPlaying != playing {
                    self.isPlaying = playing
                    self.updateNowPlayingInfo(force: true)
                }
            }
        }

        // 周期性读取播放进度
        videoTimeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.15, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated { self?.videoTick(time.seconds) }
        }
        // 播放结束回调
        if let item = player.currentItem {
            videoEndObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self, weak item] _ in
                Task { @MainActor [weak self, weak item] in
                    guard let self, let item, self.mediaPlayer?.currentItem === item else { return }
                    self.handlePlaybackFinished()
                }
            }
        }
        if let resume = restoringSession {
            nowPlaying = song
            currentTime = resume.position(limitedTo: song.duration)
            isPlaying = false
            loadLyrics(for: song)
            player.seek(to: CMTime(seconds: currentTime, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self, weak player] finished in
                Task { @MainActor [weak self, weak player] in
                    guard let self, let player, self.mediaPlayer === player, self.restoringSession != nil else { return }
                    guard finished else { self.restoringSession = nil; return }
                    if resume.wasPlaying { player.play() }
                    self.beginPlayback(of: song)
                }
            }
        } else {
            player.play()
            beginPlayback(of: song)
        }
    }

    /// 两种引擎共用的播放开始逻辑
    private func beginPlayback(of song: Song) {
        nowPlaying = song
        let resume = restoringSession
        isPlaying = resume?.wasPlaying ?? true
        userPaused = !isPlaying
        countedThisPlay = resume?.countedThisPlay ?? false
        currentTime = resume?.position(limitedTo: song.duration) ?? 0
        restoringSession = nil
        loadLyrics(for: song)
        updateNowPlayingInfo(force: true)
    }

    private func teardownVideoEngine() {
        videoStatusObserver = nil
        videoRateObserver = nil
        if let observer = videoTimeObserver {
            mediaPlayer?.removeTimeObserver(observer)
            videoTimeObserver = nil
        }
        if let observer = videoEndObserver {
            NotificationCenter.default.removeObserver(observer)
            videoEndObserver = nil
        }
        mediaPlayer?.pause()
        mediaPlayer = nil
    }

    func togglePlayPause() {
        if let mediaPlayer {
            if mediaPlayer.rate != 0 {
                mediaPlayer.pause()
                isPlaying = false
                userPaused = true
            } else {
                mediaPlayer.play()
                isPlaying = true
                userPaused = false
            }
            updateNowPlayingInfo(force: true)
            return
        }
        if let current = nowPlaying { play(current) }
        else if let first = sortedLibrary.first { playLibrary(first) }
    }

    func seek(to time: TimeInterval) {
        if let mediaPlayer {
            let clamped = max(0, min(time, duration))
            if let resume = restoringSession {
                restoringSession = nil
                isPlaying = resume.wasPlaying
                userPaused = !isPlaying
                if isPlaying { mediaPlayer.play() }
            }
            mediaPlayer.seek(to: CMTime(seconds: clamped, preferredTimescale: 600))
            currentTime = clamped
            updateNowPlayingInfo(force: true)
            return
        }
    }

    /// 自动结束先遵守单曲模式；只有推进模式或手动切歌才消费队列。
    func playNext(manual: Bool = false) {
        switch repeatMode.nextAction(manual: manual) {
        case .pause:
            mediaPlayer?.pause()
            isPlaying = false; userPaused = true
            updateNowPlayingInfo(force: true)
            return
        case .replay:
            if let current = nowPlaying { play(current) }
            return
        case .advance: break
        }
        while !upNext.isEmpty {
            let id = upNext.removeFirst()
            if let song = library.first(where: { $0.id == id }) { play(song); return }
        }
        advance(offset: 1, wrap: manual || repeatMode == .repeatAll)
    }

    func playPrevious() {
        if currentTime > 3 {
            seek(to: 0)
            return
        }
        advance(offset: -1, wrap: true)
    }

    private func advance(offset: Int, wrap: Bool) {
        let list = sessionPlaybackIDs.map { songs(for: $0) } ?? sortedLibrary
        guard !list.isEmpty else { return }
        let idx = nowPlaying.flatMap { cur in list.firstIndex { $0.id == cur.id } }
        guard var next = idx.map({ $0 + offset }) else {
            play(list[0])
            return
        }
        if next < 0 { next = wrap ? list.count - 1 : 0 }
        if next >= list.count {
            guard wrap else { return }
            next = 0
        }
        upNext = Array(list.dropFirst(next + 1)).map(\.id)
        play(list[next])
    }

    func stop(preserveSession: Bool = false) {
        restoringSession = nil
        if !preserveSession {
            UserDataFiles.save(Optional<PlaybackSession>.none, to: userData.file("playback-session.json"))
        }
        teardownVideoEngine()
        timer?.invalidate()
        timer = nil
        nowPlaying = nil
        isPlaying = false
        currentTime = 0
        lyrics = []
        MPNowPlayingInfoCenter.default().playbackState = .stopped
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    /// Small atomic checkpoints; artwork is written only when the song changes.
    func checkpointPlayback(force: Bool = true, flush: Bool = false) {
        guard restoringSession == nil, let song = nowPlaying else { return }
        guard force || Date().timeIntervalSince(lastCheckpoint) >= 1 else { return }
        let store = userData
        if lastSavedSong != song {
            UserDataFiles.save(song, to: store.file("last-playing-song.json"))
            lastSavedSong = song
        }
        let session = PlaybackSession(songID: song.id, path: song.url.path, seconds: currentTime,
                                      wasPlaying: isPlaying, countedThisPlay: countedThisPlay,
                                      contextIDs: sessionPlaybackIDs)
        UserDataFiles.save(session, to: store.file("playback-session.json"))
        lastCheckpoint = Date()
        if flush { UserDataFiles.flush() }
    }

    private func restorePlaybackSession() {
        let store = userData
        let sessionURL = store.file("playback-session.json")
        let songURL = store.file("last-playing-song.json")
        UserDataFiles.accept(sessionURL)
        UserDataFiles.accept(songURL)
        guard let data = try? Data(contentsOf: sessionURL),
              let session = try? JSONDecoder().decode(PlaybackSession.self, from: data),
              session.seconds.isFinite, session.seconds >= 0 else { return }
        let saved = (try? Data(contentsOf: songURL)).flatMap { try? JSONDecoder().decode(Song.self, from: $0) }
        let song = library.first { $0.id == session.songID || $0.url.path == session.path }
            ?? saved.flatMap { $0.id == session.songID && $0.url.path == session.path ? $0 : nil }
        guard var song else { return }
        song.relocateArtwork(root: userData.root)
        sessionPlaybackIDs = session.contextIDs
        nowPlaying = song
        currentTime = session.position(limitedTo: song.duration)
        loadLyrics(for: song)
        restoringSession = session
        startPlayback(song)
    }

    // MARK: 在线匹配文件信息（封面 / 艺人 / 专辑 / 歌词）

    private func startMetadataMatching(for songs: [Song]) {
        Task { [weak self] in
            for song in songs {
                guard let self else { return }
                await self.matchOne(song)
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }

    private func matchOne(_ song: Song) async {
        let needsCover = !song.hasArtwork
        let needsArtist = song.artist.isEmpty
        let needsAlbum = song.album.isEmpty
        let hasLocalLrc = song.autoTimedTextURL != nil
        let needsLyric = song.lyricsPath == nil && !hasLocalLrc && !song.lyricsDisabled
        guard needsCover || needsArtist || needsAlbum || needsLyric else { return }

        let generation = userDataGeneration
        let info = await MetadataMatcher.match(title: song.title, artist: song.artist)
        guard generation == userDataGeneration, let info,
              let current = library.first(where: { $0.id == song.id }),
              current.title == song.title,
              current.artist.isEmpty || current.artist == song.artist else { return }
        applyMatch(info,
                   to: song,
                   needsCover: needsCover,
                   needsArtist: needsArtist,
                   needsAlbum: needsAlbum,
                   needsLyric: needsLyric)
    }

    private func applyMatch(_ info: MatchedInfo,
                            to song: Song,
                            needsCover: Bool,
                            needsArtist: Bool,
                            needsAlbum: Bool,
                            needsLyric: Bool) {
        updateSong(song) {
            if needsArtist, $0.artist.isEmpty, let artist = info.artist, !artist.isEmpty { $0.artist = artist }
            if needsAlbum, $0.album.isEmpty, let album = info.album, !album.isEmpty { $0.album = album }
            if needsCover, $0.artworkData == nil, let data = info.coverData { $0.artworkData = data }
        }
        if needsLyric,
           let current = library.first(where: { $0.id == song.id }), !current.lyricsDisabled, current.lyricsPath == nil,
           let lrc = info.lyric, !lrc.isEmpty,
           let url = self.saveLyricsFile(lrc, title: song.title, id: song.id) {
            updateSong(song) { $0.lyricsPath = url.path }
            if nowPlaying?.id == song.id,
               let updated = library.first(where: { $0.id == song.id }) {
                loadLyrics(for: updated)
            }
        }
        matchActivity = ActivityMessage(text: "已为《\(song.title)》匹配文件信息")
    }

    private func saveLyricsFile(_ content: String, title: String, id: UUID) -> URL? {
        let dir = userData.file("Lyrics")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safeName = title.replacingOccurrences(
            of: "[/\\\\:\\*\\?\"<>|]",
            with: "_",
            options: .regularExpression
        )
        let url = dir.appendingPathComponent("\(String(safeName.prefix(40)))-\(id.uuidString).lrc")
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    // MARK: 播放结束（AVAudioPlayerDelegate）

    private func handlePlaybackFinished() {
        guard let song = nowPlaying else { return }
        currentTime = song.duration
        switch repeatMode {
        case .playOnce:
            // 单曲播放完暂停
            isPlaying = false
            userPaused = true
            updateNowPlayingInfo(force: true)
        case .repeatOne, .repeatAll:
            playNext()
        }
    }

    // MARK: 系统「播放中」（Now Playing）+ 远程控制

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        for command in [center.playCommand, center.pauseCommand, center.togglePlayPauseCommand,
                        center.nextTrackCommand, center.previousTrackCommand,
                        center.skipForwardCommand, center.skipBackwardCommand, center.changePlaybackPositionCommand] {
            command.isEnabled = true
        }
        center.skipForwardCommand.preferredIntervals = [5]
        center.skipBackwardCommand.preferredIntervals = [5]
        center.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.seek(to: self.currentTime + 5)
            }
            return .success
        }
        center.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.seek(to: self.currentTime - 5)
            }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let time = event.positionTime
            Task { @MainActor [weak self] in self?.seek(to: time) }
            return .success
        }
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.remotePlay() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.remotePause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.playNext(manual: true) }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.playPrevious() }
            return .success
        }
    }

    private func remotePlay() {
        if let mediaPlayer {
            mediaPlayer.play()
            isPlaying = true
            userPaused = false
        } else if let first = sortedLibrary.first {
            playLibrary(first)
            return
        }
        updateNowPlayingInfo(force: true)
    }

    private func remotePause() {
        // Remote pause is idempotent, including when video is buffering and
        // the published playing flag temporarily differs from the engine.
        mediaPlayer?.pause()
        isPlaying = false
        userPaused = true
        updateNowPlayingInfo(force: true)
    }

    private var remoteArtworkID: String?
    private var remoteArtwork: MPMediaItemArtwork?
    private func updateNowPlayingInfo(force: Bool = false) {
        checkpointPlayback(force: force)
        let center = MPNowPlayingInfoCenter.default()
        guard let song = nowPlaying else {
            center.playbackState = .stopped
            center.nowPlayingInfo = nil
            return
        }
        center.playbackState = isPlaying ? .playing : .paused
        if !force, abs(currentTime - lastElapsedReport) < 5 { return }
        lastElapsedReport = currentTime

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.title,
            MPMediaItemPropertyArtist: song.artist.isEmpty ? "未知艺人" : song.artist,
            MPMediaItemPropertyAlbumTitle: song.album,
            MPMediaItemPropertyPlaybackDuration: song.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: (isVideo ? MPNowPlayingInfoMediaType.video : .audio).rawValue
        ]
        if remoteArtworkID != song.artworkID {
            remoteArtworkID = song.artworkID
            remoteArtwork = nil
            if let data = song.artworkData, let thumbnail = ArtworkRendering.thumbnail(data, maximum: 512) {
                let image = ArtworkRendering.native(thumbnail)
                remoteArtwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            }
        }
        if let remoteArtwork { info[MPMediaItemPropertyArtwork] = remoteArtwork }
        center.nowPlayingInfo = info
    }

    // MARK: 定时刷新

    /// 视频播放进度回调（AVPlayer 周期观察者）
    private func videoTick(_ seconds: TimeInterval) {
        guard restoringSession == nil, let song = nowPlaying, mediaPlayer != nil else { return }
        let playing = (mediaPlayer?.rate ?? 0) != 0
        if isPlaying != playing { isPlaying = playing }
        currentTime = max(0, seconds)
        if !countedThisPlay, song.duration > 1, currentTime >= song.duration / 3 {
            countedThisPlay = true
            incrementPlayCount(song)
        }
        updateNowPlayingInfo()
    }

    // MARK: 资料库持久化（Application Support/LyricPlayer/library.json）

    private var libraryURL: URL { userData.file("library.json") }

    private let persistence = LibraryPersistence()
    private var artworkMigration: Task<Void, Never>?
    private func saveLibrary() { persistence.save(library, to: libraryURL); migrateEmbeddedArtwork() }
    func flushLibrarySaves() { persistence.flush(); scanPersistence.flush() }

    private func loadLibrary() {
        guard FileManager.default.fileExists(atPath: libraryURL.path) else { return }
        do {
            let revision = UserDataFiles.revision(libraryURL)
            let data = try Data(contentsOf: libraryURL)
            var songs = try JSONDecoder().decode([Song].self, from: data)
            guard Set(songs.map(\.id)).count == songs.count,
                  Set(songs.map(\.path)).count == songs.count,
                  songs.allSatisfy({ !$0.path.isEmpty && $0.duration.isFinite && $0.duration >= 0 && $0.lyricsOffset.isFinite }) else { throw CocoaError(.fileReadCorruptFile) }
            for i in songs.indices {
                songs[i].lyricsPath = userData.managedLyricsPath(songs[i].lyricsPath)
                songs[i].relocateArtwork(root: userData.root)
            }
            guard UserDataFiles.accept(libraryURL, expectedRevision: revision) else { return }
            library = songs
            migrateEmbeddedArtwork()
            SongLibraryCache.existing = Dictionary(uniqueKeysWithValues: songs.map { ($0.path, $0) })
            if let playing = nowPlaying, let restored = songs.first(where: { $0.id == playing.id }) {
                nowPlaying = restored
                loadLyrics(for: restored)
                updateNowPlayingInfo(force: true)
            }
        } catch { userData.report("library.json 无法读取，当前资料库保留，文件不会被覆盖。") }
    }
    private func migrateEmbeddedArtwork() {
        guard artworkMigration == nil, library.contains(where: { $0.embeddedArtwork != nil }) else { return }
        let snapshot = library.filter { $0.embeddedArtwork != nil }
        let root = userData.root
        let source = libraryURL
        let generation = userDataGeneration
        artworkMigration = Task { [weak self] in
            let results = await Task.detached(priority: .utility) {
                let backup = root.appendingPathComponent("library-before-artwork-migration.json")
                if FileManager.default.fileExists(atPath: source.path) && !FileManager.default.fileExists(atPath: backup.path) {
                    do { try FileManager.default.copyItem(at: source, to: backup) }
                    catch { return [ArtworkStorage.Result]() }
                }
                return ArtworkStorage.externalize(snapshot, root: root)
            }.value
            guard let self else { return }
            defer { self.artworkMigration = nil }
            guard generation == self.userDataGeneration, !Task.isCancelled else { return }
            let byID = Dictionary(uniqueKeysWithValues: results.map { ($0.id, $0) })
            var next = self.library
            var changed = false
            for i in next.indices {
                if let result = byID[next[i].id], result.revision == next[i].artworkRevision {
                    next[i].useStoredArtwork(at: result.path); changed = true
                }
            }
            guard changed else { return }
            self.library = next
            SongLibraryCache.existing = Dictionary(uniqueKeysWithValues: next.map { ($0.path, $0) })
            if let current = self.nowPlaying, let updated = next.first(where: { $0.id == current.id }) { self.nowPlaying = updated }
            self.persistence.save(next, to: self.libraryURL)
            self.checkpointPlayback(force: true)
        }
    }

    private func reloadQueue() {
        let url = userData.file("queue.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let revision = UserDataFiles.revision(url)
            let ids = try JSONDecoder().decode([UUID].self, from: Data(contentsOf: url))
            guard UserDataFiles.accept(url, expectedRevision: revision) else { return }
            loadingUserData = true
            var seen = Set<UUID>()
            upNext = ids.filter { seen.insert($0).inserted }
            loadingUserData = false
        } catch { userData.report("queue.json 无法读取，当前队列保留。") }
    }
    private func reloadUserData(_ names: Set<String>) {
        userDataGeneration += 1
        if names.contains("library.json") { loadLibrary() }
        if names.contains("queue.json") { reloadQueue() }
        if names.contains("folder-scan.json") {
            do {
                let revision = UserDataFiles.revision(scanCatalogURL)
                let saved = try JSONDecoder().decode(FolderScanCatalog.self, from: Data(contentsOf: scanCatalogURL))
                guard UserDataFiles.accept(scanCatalogURL, expectedRevision: revision) else { return }
                scanCatalog = saved
                watchedFolders = saved.folders
                scanConfigurationLoaded = true
            } catch { userData.report("folder-scan.json 无法读取，原文件及当前排除记录保留。") }
        }
        if names.contains("Lyrics"), let song = nowPlaying { loadLyrics(for: song) }
        if names.contains("preferences.plist") {
            let d = userData.defaults
            repeatMode = RepeatMode(rawValue: d.string(forKey: "repeatMode") ?? "") ?? .repeatAll
            sortKey = SortKey(rawValue: d.string(forKey: "sortKey") ?? "") ?? .title
            sortAscending = d.object(forKey: "sortAscending") as? Bool ?? true
            usesCustomLibraryOrder = d.bool(forKey: "usesCustomLibraryOrder")
            autoScanFolders = d.object(forKey: "autoScanFolders") as? Bool ?? true
        }
    }
}
