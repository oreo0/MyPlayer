import SwiftUI
import AppKit

struct QueuePanel: View {
    @ObservedObject var player: PlayerManager
    @Environment(\.self) private var environment
    private var currentTitleColor: NSColor {
        let color = Color.accentColor.resolve(in: environment)
        return NSColor(srgbRed: CGFloat(color.red), green: CGFloat(color.green), blue: CGFloat(color.blue), alpha: CGFloat(color.opacity))
    }
    var isActive = true
    @State private var scrolling = false
    @State private var contentAboveTop = false
    var bottomClearance: CGFloat = 110
    let close: () -> Void
    @State private var editingSong: Song?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var songs: [Song] {
        let waiting = player.queuedSongs.filter { $0.id != player.nowPlaying?.id }
        return player.nowPlaying.map { [$0] + waiting } ?? waiting
    }
    var body: some View {
        let displayed = songs
        let numberWidth = MediaRowMetrics.numberWidth(count: displayed.count)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("播放队列 · \(displayed.count)")
                    .font(.system(size: 32, weight: .black)).lineLimit(1).minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("清空", action: player.confirmClearQueue)
                    .buttonStyle(.glass).buttonBorderShape(.roundedRectangle(radius: 10))
                    .disabled(player.upNext.isEmpty)
                Button(action: close) { Image(systemName: "xmark").frame(width: 16, height: 16) }
                    .buttonStyle(.glass).buttonBorderShape(.circle)
                    .help("关闭播放队列")
            }
            .padding(.horizontal, 12).frame(minHeight: 66)
            .zIndex(1)
            List {
                ForEach(Array(displayed.enumerated()), id: \.element.id) { index, song in
                    let current = player.nowPlaying?.id == song.id
                    HStack(spacing: 8) {
                        Group {
                            if current {
                                Image(systemName: "waveform").foregroundStyle(Color.accentColor)
                                    .symbolEffect(.variableColor.iterative, options: .repeating, isActive: player.isPlaying && !reduceMotion)
                            } else { Text("\(player.nowPlaying == nil ? index + 1 : index)").monospacedDigit().lineLimit(1).fixedSize(horizontal: true, vertical: false).foregroundStyle(.secondary) }
                        }.frame(width: numberWidth)
                        VStack(alignment: .leading, spacing: 3) {
                            ScrollingSongTitle(text: song.title, height: 20, isActive: isActive && !scrolling,
                                               textColor: current ? currentTitleColor : .labelColor)
                            ScrollingSongTitle(text: song.artist, height: 16, isActive: isActive && !scrolling,
                                               fontSize: NSFont.smallSystemFontSize, textColor: .secondaryLabelColor)
                        }.frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                            .layoutPriority(1)
                        Text(formatTime(song.duration)).font(.caption).monospacedDigit().lineLimit(1).fixedSize()
                        Button { player.confirmRemoveFromQueue(song) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless).help("从播放队列移除")
                    }
                    .frame(height: MediaRowMetrics.contentHeight).contentShape(Rectangle())
                    .listRowInsets(MediaRowMetrics.insets)
                    .listRowSeparator(.hidden)
                    .onTapGesture(count: 2) { if !current { player.playQueued(song) } }
                    .listRowBackground(Color.clear)
                    .contextMenu {
                        MediaContextMenu(song: song, play: { player.playQueued(song) }, edit: { editingSong = song }, removalTitle: "从播放队列移除", remove: { player.confirmRemoveFromQueue(song) })
                    }
                }
            }.listStyle(.plain).scrollContentBackground(.hidden)
                .scrollEdgeEffectHidden()
                .mask {
                    VStack(spacing: 0) {
                        LinearGradient(colors: [contentAboveTop ? .clear : .white, .white], startPoint: .top, endPoint: .bottom).frame(height: 28)
                        Color.white
                    }
                }
                .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > 1 } action: { _, value in contentAboveTop = value }
                .onScrollPhaseChange { _, phase in scrolling = phase != .idle }
                
                .contentMargins(.bottom, bottomClearance, for: .scrollContent)
                .overlay { if songs.isEmpty { ContentUnavailableView("队列为空", systemImage: "list.bullet") } }
        }
        .sheet(item: $editingSong) { MediaInfoEditor(song: $0).environmentObject(player) }
    }
}
