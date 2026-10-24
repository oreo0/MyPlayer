import SwiftUI
import AppKit

struct VideoLyricsStrip: View {
    @ObservedObject var player: PlayerManager
    @ObservedObject var clock: PlaybackClock
    var isActive: Bool
    @AppStorage("videoLyricsStyle") private var style = "single"
    @AppStorage("videoLyricsSize") private var size = 30.0
    @AppStorage("videoLyricsFont") private var family = "system"
    private var lyricFont: Font {
        let pointSize = min(72, max(28, size))
        let fontWeight = (LyricsWeight(rawValue: weight) ?? .bold).weight
        return family == "system" ? .system(size: pointSize, weight: fontWeight) : .custom(family, size: pointSize).weight(fontWeight)
    }
    @AppStorage("videoLyricsWeight") private var weight = "bold"
    @State private var availableWidth: CGFloat = 800
    private var lineHeight: CGFloat {
        let pointSize = min(72, max(28, size))
        let font = (family == "system" ? nil : NSFont(name: family, size: pointSize)) ?? NSFont.systemFont(ofSize: pointSize)
        return ceil(font.ascender - font.descender + font.leading)
    }
    private var current: Int? { LRCParser.currentIndex(for: player.lyrics, at: clock.time - (player.nowPlaying?.lyricsOffset ?? 0)) }
    var body: some View {
        VStack(spacing: max(2, size * 0.06)) {
            if style == "ktv" {
                let base = (current ?? 0) / 2 * 2
                line(base, alignment: .leading)
                line(base + 1, alignment: .trailing)
            } else {
                line(current ?? -1, alignment: .center)
            }
        }
        .padding(.horizontal, style == "ktv" ? max(40, min(96, availableWidth * 0.08)) : 24).padding(.vertical, max(3, size * 0.1))
        .fixedSize(horizontal: false, vertical: true)
        .layoutPriority(1)
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
        .background(Color.black)
        .accessibilityElement(children: .contain)
    }
    @ViewBuilder private func line(_ index: Int, alignment: Alignment) -> some View {
        let text = player.lyrics.indices.contains(index) ? player.lyrics[index].text : " "
        let now = clock.time - (player.nowPlaying?.lyricsOffset ?? 0)
        let expired = player.lyrics.indices.contains(index) && player.lyrics[index].endTime.map { now >= $0 } == true
        let shownText = expired && style != "ktv" ? " " : text
        let progress = TimedTextParser.progress(lines: player.lyrics, index: index, time: clock.time, offset: player.nowPlaying?.lyricsOffset ?? 0, duration: player.duration)
        Text(shownText)
            .font(lyricFont)
            .multilineTextAlignment(alignment == .leading ? .leading : (alignment == .trailing ? .trailing : .center))
            .lineLimit(1).minimumScaleFactor(0.35)
            .foregroundStyle(Color.white.opacity(style == "ktv" ? 0.38 : 1))
            .overlay {
                if style == "ktv" {
                    GeometryReader { geometry in
                        Text(shownText)
                            .font(lyricFont)
                            .lineLimit(1).minimumScaleFactor(0.35).foregroundStyle(Color.white)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .mask(alignment: .leading) { Rectangle().frame(width: geometry.size.width * progress) }
                            .animation(.linear(duration: 0.15), value: progress)
                    }.allowsHitTesting(false)
                }
            }
            .frame(height: lineHeight, alignment: .center)
            .frame(maxWidth: .infinity, alignment: alignment)
    }
}
