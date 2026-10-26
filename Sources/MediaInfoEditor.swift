import SwiftUI
import UniformTypeIdentifiers
import PhotosUI

extension Notification.Name {
    static let locateCurrentMedia = Notification.Name("MyPlayer.locateCurrentMedia")
}

struct MediaFileActions: View {
    let song: Song
    let edit: () -> Void
    var body: some View {
        Button("在访达中显示该文件") { NSWorkspace.shared.activateFileViewerSelecting([song.url]) }
        Button("修改文件信息…", action: edit)
    }
}

struct MediaInfoEditor: View {
    @EnvironmentObject private var player: PlayerManager
    @Environment(\.dismiss) private var dismiss
    let song: Song
    @State private var title: String
    @State private var artist: String
    @State private var album: String
    @State private var artwork: Data?
    @State private var imageError = false
    @State private var editorID = UUID()
    @State private var playbackContinuity: MetadataPlaybackContinuity?
    @State private var showFilePicker = false
    @State private var showPhotosPicker = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var loadingArtwork = false
    @State private var artworkTask: Task<Void, Never>?
    @State private var saving = false
    @State private var saveError: String?
    @State private var showSaveError = false
    init(song: Song) {
        self.song = song
        _title = State(initialValue: song.title)
        _artist = State(initialValue: song.artist)
        _album = State(initialValue: song.album)
        _artwork = State(initialValue: song.artworkData)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("修改文件信息").font(.title2.bold())
            HStack(spacing: 20) {
                Group {
                    if let artwork, let image = NSImage(data: artwork) {
                        Image(nsImage: image).resizable().scaledToFit()
                    } else { Image(systemName: "opticaldisc").font(.system(size: 54)).foregroundStyle(.secondary) }
                }.frame(width: 120, height: 120)
                VStack(alignment: .leading) {
                    Menu("选择专辑封面…") {
                        Button("从访达选择…") { showFilePicker = true }
                        Button("从照片选择…") { showPhotosPicker = true }
                    }
                    if loadingArtwork { ProgressView().controlSize(.small) }
                    Button("移除封面") { RemovalConfirmation.request("移除封面？", message: "保存信息后，该文件将不再使用当前封面。") { artwork = nil } }.disabled(artwork == nil)
                }
            }
            Form {
                TextField("标题", text: $title)
                TextField("艺人名", text: $artist)
                TextField("专辑名", text: $album)
            }
            Text("信息与封面将写入源文件，并按“标题 - 艺人”重命名。原文件会先保存在本机备份文件夹。").font(.caption).foregroundStyle(.secondary)
            HStack {
                if saving { ProgressView().controlSize(.small); Text("正在保存源文件…").font(.caption) }
                Spacer()
                Button("取消") { dismiss() }.buttonStyle(.glass).keyboardShortcut(.cancelAction)
                Button("保存") {
                    saving = true
                    Task {
                        do { try await player.editSourceMetadata(song, title: title, artist: artist, album: album, artwork: artwork); dismiss() }
                        catch { saveError = error.localizedDescription; showSaveError = true }
                        saving = false
                    }
                }.buttonStyle(.glassProminent).keyboardShortcut(.defaultAction).disabled(loadingArtwork || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.disabled(saving).padding(24).frame(width: 500)
        .onAppear {
            InteractionActivity.shared.editing(editorID, began: true)
            playbackContinuity = MetadataPlaybackContinuity(player: player)
        }
        .onDisappear {
            playbackContinuity?.invalidate(); playbackContinuity = nil
            artworkTask?.cancel(); InteractionActivity.shared.editing(editorID, began: false)
        }
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.image], allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            artworkTask?.cancel(); loadingArtwork = true
            artworkTask = Task {
                defer { loadingArtwork = false }
                do { let loaded = try await CoverImageImport.file(url); guard !Task.isCancelled else { return }; artwork = loaded }
                catch { if !Task.isCancelled { imageError = true } }
            }
        }
        .photosPicker(isPresented: $showPhotosPicker, selection: $selectedPhoto, matching: .images, preferredItemEncoding: .current)
        .task(id: selectedPhoto) {
            guard let selectedPhoto else { return }
            loadingArtwork = true; defer { loadingArtwork = false }
            do {
                guard let data = try await selectedPhoto.loadTransferable(type: Data.self) else { imageError = true; return }
                let loaded = try await CoverImageImport.photo(data)
                guard !Task.isCancelled else { return }; artwork = loaded
            } catch { if !Task.isCancelled { imageError = true } }
        }
        .interactiveDismissDisabled(saving)
        .presentationSizing(.fitted)
        .presentationBackground(.regularMaterial)
        .nativeDialog("无法读取该图片，请选择有效的图片文件。", isPresented: $imageError)
        .nativeDialog(saveError ?? "保存失败。", isPresented: $showSaveError)
    }

}

/// Extend scrolling content beneath the header, fading the real backdrop into it.
struct ProgressivePanelHeader: ViewModifier {
    func body(content: Content) -> some View {
        content.background {
            WithinWindowBlur(atTop: true)
                .padding(.bottom, -24)
                .allowsHitTesting(false)
        }.zIndex(1)
    }
}
