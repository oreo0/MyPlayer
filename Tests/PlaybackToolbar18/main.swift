import AppKit
import SwiftUI
@MainActor final class AppDelegate: NSObject { func bindWindow(_ window: NSWindow) {} }
@main struct Toolbar18Tests {
    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 650), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        let toolbar = NSToolbar(identifier: "Playback18Tests")
        window.toolbar = toolbar
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        let accessory = NSTitlebarAccessoryViewController()
        accessory.view = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 20))
        accessory.fullScreenMinHeight = 20
        window.addTitlebarAccessoryViewController(accessory)
        let anchor = PlaybackToolbarPresentation.AppearanceView()
        window.contentView!.addSubview(anchor)
        let frame = window.frame
        for _ in 0..<100 {
            anchor.configure(playback: true, hidden: true); anchor.apply()
            precondition(window.toolbar === toolbar && !toolbar.isVisible, "hide the entire native toolbar without detaching SwiftUI ownership")
            precondition(accessory.isHidden && accessory.fullScreenMinHeight == 0, "no retained accessory backdrop")
            precondition(window.titleVisibility == .hidden && window.titlebarAppearsTransparent)
            anchor.configure(playback: true, hidden: false); anchor.apply()
            precondition(window.toolbar === toolbar && toolbar.isVisible)
            precondition(!accessory.isHidden && !accessory.view.isHidden && accessory.fullScreenMinHeight == 20)
            precondition(window.frame == frame, "chrome visibility must not resize the window")
        }
        anchor.configure(playback: true, hidden: true); anchor.apply()
        let replacement = NSToolbar(identifier: "replacement")
        window.toolbar = replacement
        anchor.apply()
        precondition(window.toolbar === replacement && !replacement.isVisible, "hide replacement toolbar without reinstall loops")
        let host = NSWindow(contentRect: .init(x: 0, y: 0, width: 200, height: 40), styleMask: .borderless, backing: .buffered, defer: false)
        host.alphaValue = 0.65
        let originalHostAlpha = host.alphaValue
        anchor.hideFullscreenHosts([window, host, host], excluding: window)
        precondition(host.alphaValue == 0 && host.ignoresMouseEvents)
        precondition(window.alphaValue == 1, "never hide the main playback window")
        anchor.hideFullscreenHosts([host], excluding: window)
        anchor.configure(playback: false, hidden: false); anchor.apply()
        precondition(host.alphaValue == originalHostAlpha && !host.ignoresMouseEvents, "restore exact fullscreen host opacity and input state")
        precondition(window.toolbar === replacement && replacement.isVisible)
        precondition(window.titleVisibility == .visible && !window.titlebarAppearsTransparent)
        precondition(!accessory.isHidden && !accessory.view.isHidden && accessory.fullScreenMinHeight == 20)
        // An initially hidden accessory must remain hidden after restoration.
        accessory.view.isHidden = true
        anchor.configure(playback: true, hidden: true); anchor.apply()
        anchor.restore()
        precondition(accessory.view.isHidden)
        print("PASS: 100 native toolbar hide/restore cycles, zero retained accessory height, exact visibility restoration, replacement toolbar reconciliation, stable window frame")
    }
}
