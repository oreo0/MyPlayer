import Foundation
import AVFoundation
import AppKit
import UniformTypeIdentifiers

// MARK: - 文件选择

enum FileImporter {

    static let audioExtensions = ["mp3", "m4a", "aac", "wav", "aiff", "aif", "flac", "caf", "m4b"]
    /// 视频（走 AVPlayer 播放引擎）
    static let videoExtensions = Array(Song.videoExtensions)
    /// 拖拽/导入时接受的所有媒体格式
    static var supportedExtensions: [String] { audioExtensions + videoExtensions }

    struct Discovery {
        var files: [URL] = []
        var unreadable: [String] = []
    }
    static func discover(_ urls: [URL]) -> Discovery {
        var result = Discovery()
        var seen = Set<String>()
        for url in urls {
            var directory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) else {
                result.unreadable.append(url.lastPathComponent); continue
            }
            if !directory.boolValue {
                if seen.insert(FolderScanCatalog.key(url)).inserted { result.files.append(url) }
                continue
            }
            guard FileManager.default.isReadableFile(atPath: url.path) else {
                result.unreadable.append(url.lastPathComponent); continue
            }
            let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) { failed, _ in
                result.unreadable.append(failed.lastPathComponent)
                return true
            }
            if enumerator == nil { result.unreadable.append(url.lastPathComponent) }
            while let file = enumerator?.nextObject() as? URL {
                guard (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                if seen.insert(FolderScanCatalog.key(file)).inserted { result.files.append(file) }
            }
        }
        return result
    }
    static func expandDroppedURLs(_ urls: [URL]) -> [URL] { discover(urls).files }

    @MainActor private static var activeMediaPanel: NSOpenPanel?
    @MainActor static func pickAudioFiles(completion: @escaping ([URL]) -> Void) {
        presentMediaPanel(folders: false, completion: completion)
    }
    @MainActor static func pickAudioFolder(completion: @escaping ([URL]) -> Void) {
        presentMediaPanel(folders: true, completion: completion)
    }
    @MainActor private static func presentMediaPanel(folders: Bool, completion: @escaping ([URL]) -> Void) {
        // Wait until menu tracking finishes; never run a nested modal loop here.
        DispatchQueue.main.async {
            guard activeMediaPanel == nil else { activeMediaPanel?.makeKeyAndOrderFront(nil); return }
            let panel = NSOpenPanel()
            activeMediaPanel = panel
            panel.title = folders ? "选择音乐文件夹" : "选择音乐 / 视频文件"
            panel.canChooseFiles = !folders
            panel.canChooseDirectories = folders
            panel.allowsMultipleSelection = true
            if !folders {
                panel.allowedContentTypes = [.audio, .movie, .video] + supportedExtensions.compactMap { UTType(filenameExtension: $0) }
                panel.allowsOtherFileTypes = true
            }
            let finished: (NSApplication.ModalResponse) -> Void = { response in
                let urls = response == .OK ? panel.urls : []
                activeMediaPanel = nil
                if !urls.isEmpty { completion(urls) }
            }
            NSApp.activate(ignoringOtherApps: true)
            if let window = NSApp.keyWindow ?? NSApp.mainWindow, window.attachedSheet == nil {
                panel.beginSheetModal(for: window, completionHandler: finished)
            } else { panel.begin(completionHandler: finished) }
        }
    }

    @MainActor
    static func pickLyricsFile() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "选择歌词 / 字幕文件"
        panel.canChooseFiles = true
        panel.allowedContentTypes = ["lrc", "srt", "vtt"].compactMap { UTType(filenameExtension: $0) } + [.plainText]
        panel.allowsOtherFileTypes = true
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}
