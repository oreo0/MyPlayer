import SwiftUI
import AppKit
@MainActor final class AppDelegate: NSObject { func bindWindow(_ window: NSWindow) {} }
@main struct Interface49Tests {
    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 500, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let marquee = TitleMarquee.MarqueeView(frame: .init(x: 0, y: 0, width: 70, height: 20))
        window.contentView!.addSubview(marquee)
        let title = String(repeating: "Very long song and artist name ", count: 10)
        marquee.configure(text: title, active: true, fontSize: 13, textColor: .systemRed)
        marquee.layoutSubtreeIfNeeded()
        let label = marquee.subviews.first as! NSTextField
        precondition(label.font?.pointSize == 13 && label.textColor == .systemRed)
        precondition(label.layer?.animation(forKey: "titleScroll") != nil)
        let count = marquee.animationRebuilds
        for _ in 0..<2000 {
            marquee.configure(text: title, active: true, fontSize: 13, textColor: .systemRed)
            marquee.layoutSubtreeIfNeeded()
        }
        precondition(marquee.animationRebuilds == count)
        marquee.configure(text: title, active: true, fontSize: 13, textColor: .systemGreen)
        marquee.layoutSubtreeIfNeeded()
        precondition(marquee.animationRebuilds == count && label.textColor == .systemGreen)
        marquee.frame.size.width = 10000; marquee.layoutSubtreeIfNeeded()
        precondition(label.layer?.animation(forKey: "titleScroll") == nil)
        marquee.frame.size.width = 60; marquee.layoutSubtreeIfNeeded()
        precondition(label.layer?.animation(forKey: "titleScroll") != nil)
        marquee.configure(text: title, active: false, fontSize: NSFont.smallSystemFontSize, textColor: .secondaryLabelColor)
        marquee.layoutSubtreeIfNeeded()
        precondition(label.layer?.animation(forKey: "titleScroll") == nil)
        precondition(label.font?.pointSize == NSFont.smallSystemFontSize)
        let fixture = HStack(spacing: 0) {
            ToolbarIconButton("歌词", systemImage: "text.bubble") {}
            Menu("视图", systemImage: "list.bullet") { Button("列表") {} }
                .frame(width: ToolbarControlMetrics.size, height: ToolbarControlMetrics.size)
        }.labelStyle(.iconOnly).buttonStyle(.borderless)
            .font(.system(size: ToolbarControlMetrics.iconSize, weight: .regular)).imageScale(.medium)
            .menuStyle(.borderlessButton).menuIndicator(.hidden).controlSize(.regular)
        let hosting = NSHostingView(rootView: fixture)
        window.contentView!.addSubview(hosting)
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        precondition(abs(size.width - 64) <= 1 && abs(size.height - 32) <= 1)
        window.close()
        print("PASS: native title/artist marquee overflow and resize behavior; color-only updates preserve animation; 2,000 stable configurations; button/menu sizing 32x32")
    }
}
