import SwiftUI
import UniformTypeIdentifiers

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
                    Button("选择专辑封面…", action: chooseArtwork)
                    Button("移除封面") { RemovalConfirmation.request("移除封面？", message: "保存信息后，该文件将不再使用当前封面。") { artwork = nil } }.disabled(artwork == nil)
                }
            }
            Form {
                TextField("文件名", text: $title)
                TextField("艺人名", text: $artist)
                TextField("专辑名", text: $album)
            }
            Text("信息保存到 MyPlayer 资料库。").font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("取消") { dismiss() }.buttonStyle(.glass).keyboardShortcut(.cancelAction)
                Button("保存") {
                    player.editMetadata(song, title: title, artist: artist, album: album, artwork: artwork)
                    dismiss()
                }.buttonStyle(.glassProminent).keyboardShortcut(.defaultAction).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 460)
        .presentationSizing(.fitted)
        .presentationBackground(.regularMaterial)
        .nativeDialog("无法读取该图片，请选择有效的图片文件。", isPresented: $imageError)
    }
    private func chooseArtwork() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url), let image = ArtworkRendering.thumbnail(data, maximum: 1024),
              let encoded = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { imageError = true; return }
        artwork = encoded
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
