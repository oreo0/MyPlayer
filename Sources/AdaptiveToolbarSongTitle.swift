import SwiftUI
import AppKit

/// The natural text width is the ideal width, rather than a fixed title slot.
/// Native toolbar compression can reduce it; the existing layer marquee then scrolls.
struct AdaptiveToolbarSongTitle: View {
    let text: String
    let active: Bool
    let color: NSColor
    @MainActor private static let widths: NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>(); cache.countLimit = 128; return cache
    }()
    @MainActor static func naturalWidth(_ text: String) -> CGFloat {
        let key = text as NSString
        if let cached = widths.object(forKey: key) { return CGFloat(cached.doubleValue) }
        // Match the real NSTextField's padding as well as its glyph width.
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: NSFont.systemFontSize)
        label.maximumNumberOfLines = 1; label.lineBreakMode = .byClipping
        let width = ceil(label.fittingSize.width) + 1
        widths.setObject(NSNumber(value: Double(width)), forKey: key)
        return width
    }
    var body: some View {
        let width = Self.naturalWidth(text)
        ScrollingSongTitle(text: text, isActive: active, textColor: color)
            .frame(minWidth: min(32, width), idealWidth: width, maxWidth: width)
    }
}
struct ToolbarTabHighlight: ViewModifier {
    let selected: Bool
    let accent: Color
    func body(content: Content) -> some View {
        content.background(selected ? accent.opacity(0.18) : .clear, in: Capsule())
            .accessibilityValue(selected ? "已选中" : "未选中")
    }
}
