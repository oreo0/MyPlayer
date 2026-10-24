import SwiftUI

/// Shared order and labels for media rows, regardless of their layout or source.
struct MediaContextMenu: View {
    @EnvironmentObject private var player: PlayerManager
    let song: Song
    var collectionIDs: [UUID] = []
    let play: () -> Void
    let edit: () -> Void
    var createCollection: (() -> Void)? = nil
    let removalTitle: String
    let remove: () -> Void
    var body: some View {
        Section("播放") {
            Button("立即播放", action: play)
            Button("下一首播放") { player.queueNext(song) }
            Button("添加到播放队列末尾") { player.enqueue(song) }
        }
        Section("收藏与合集") {
            Button(song.isFavorite ? "取消喜欢" : "喜欢") { player.confirmToggleFavorite(song) }
            if let createCollection {
                AddToCollectionMenu(ids: collectionIDs.isEmpty ? [song.id] : collectionIDs, create: createCollection)
            }
        }
        Section("歌词") {
            Button("选择歌词 / 字幕文件…") { player.chooseLyrics(for: song) }
            Button("取消匹配当前歌词文件") { player.confirmUnmatchLyrics(for: song) }
                .disabled(song.lyricsDisabled || (song.lyricsPath == nil && song.autoTimedTextURL == nil))
        }
        Section("文件与信息") { MediaFileActions(song: song, edit: edit) }
        Section("移除") { Button(removalTitle, role: .destructive, action: remove) }
    }
}

struct LyricLineContextMenu: View {
    @EnvironmentObject private var player: PlayerManager
    let time: TimeInterval
    @Binding var following: Bool
    @Binding var blur: Bool
    @Binding var centered: Bool
    var body: some View {
        Section("播放") {
            Button("从这句开始播放") {
                following = true
                player.seek(to: time + (player.nowPlaying?.lyricsOffset ?? 0))
                if player.nowPlaying != nil && !player.isPlaying { player.togglePlayPause() }
            }
        }
        Section("歌词显示") {
            Toggle("自动跟随当前歌词", isOn: $following)
            Toggle("歌词模糊", isOn: $blur)
            Toggle("歌词居中", isOn: $centered)
        }
        Section("歌词同步") {
            Button("歌词提前 0.2 秒") { player.adjustLyrics(by: -0.2) }
            Button("歌词延后 0.2 秒") { player.adjustLyrics(by: 0.2) }
            Button("重置歌词同步") { player.resetLyricsOffset() }
        }
        if let song = player.nowPlaying {
            Section("歌词文件") {
                Button("选择歌词 / 字幕文件…") { player.chooseLyrics(for: song) }
                Button("取消匹配当前歌词文件") { player.confirmUnmatchLyrics(for: song) }
                    .disabled(song.lyricsDisabled || (song.lyricsPath == nil && song.autoTimedTextURL == nil))
            }
        }
    }
}
