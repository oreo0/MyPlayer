import AppKit
import AVFoundation
import SwiftUI

@MainActor final class AppDelegate: NSObject { func bindWindow(_ window: NSWindow) {} }
@main struct InterfaceTests {
    @MainActor static func main() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let root = NSView(), content = NSView()
        let titleBackdrop = NSVisualEffectView(), lyricBackdrop = NSVisualEffectView()
        root.addSubview(titleBackdrop); root.addSubview(content); content.addSubview(lyricBackdrop)
        let original = NSImage(size: NSSize(width: 4, height: 4))
        titleBackdrop.maskImage = original
        let anchor = FullscreenToolbarTransparency.Anchor()
        anchor.clearBackdrop(in: root, excluding: content)
        let cleared = titleBackdrop.maskImage
        precondition(cleared != nil && cleared !== original)
        precondition(lyricBackdrop.maskImage == nil, "do not clear content materials")
        for _ in 0..<100 { anchor.clearBackdrop(in: root, excluding: content) }
        precondition(titleBackdrop.maskImage === cleared)
        anchor.restore()
        precondition(titleBackdrop.maskImage === original, "restore exact prior native backdrop")
        for width in stride(from: 800.0, through: 2400, by: 10) {
            for overlay in [false, true] {
                let range = SidePanelMetrics.limits(for: width, overlay: overlay)
                for preferred in [0.0, 100, 320, 600, 10000] {
                    let actual = SidePanelMetrics.resolvedWidth(for: width, preferred: preferred, overlay: overlay)
                    precondition(range.contains(actual))
                    precondition(actual <= width - (overlay ? 80 : 450))
                }
            }
        }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("MyPlayer48-\(UUID().uuidString)")
        let suite = "MyPlayer.Test48.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: temp) }
        let store = UserDataStore(root: temp, defaults: defaults)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(fromPropertyList: ["sidePanelPreferredWidth": 420.0], format: .binary, options: 0)
        try plist.write(to: store.file("preferences.plist")); store.prepare()
        precondition(defaults.double(forKey: "sidePanelPreferredWidth") == 420)
        let player = AVPlayer(url: URL(fileURLWithPath: CommandLine.arguments[1]))
        let item = player.currentItem!
        let appearance = PlaybackAppearance()
        var sample = false
        let task = Task { @MainActor in await appearance.observe(song: nil, video: player, active: true, darkLyrics: false, shouldSample: { sample }) }
        try await Task.sleep(for: .milliseconds(100))
        let output = item.outputs.first!
        precondition(item.outputs.count == 1)
        for i in 0..<3 {
            sample = i % 2 == 0
            try await Task.sleep(for: .milliseconds(2600))
            precondition(item.outputs.count == 1 && item.outputs.first === output, "focus/visibility cannot reattach video output")
        }
        task.cancel(); await task.value
        precondition(item.outputs.isEmpty)
        print("PASS: titlebar material masking/restoration, unchanged content materials, sidebar sizing/preferences, stable video output lifecycle")
    }
}
