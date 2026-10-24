import SwiftUI
import AppKit
import Combine
import QuartzCore

/// Keep SwiftUI's window and playback surface alive when entering background mode.
@MainActor
final class MainWindowLifecycle: NSObject, NSWindowDelegate {
    weak var window: NSWindow?
    private weak var originalDelegate: NSWindowDelegate?
    private let player: () -> PlayerManager?

    init(window: NSWindow, player: @escaping () -> PlayerManager?) {
        self.window = window
        self.originalDelegate = window.delegate
        self.player = player
        super.init()
        window.delegate = self
    }
    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || originalDelegate?.responds(to: selector) == true
    }
    override func forwardingTarget(for selector: Selector!) -> Any? {
        originalDelegate?.responds(to: selector) == true ? originalDelegate : super.forwardingTarget(for: selector)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        player()?.checkpointPlayback(flush: true)
        guard UserDefaults.standard.string(forKey: "closeWindowBehavior") == "background" else {
            NSApp.terminate(nil)
            return false
        }
        // Returning false avoids tearing down the SwiftUI scene / AVPlayerView.
        showBackgroundIndicator()
        sender.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
        return false
    }
    func restoreWindow() {
        NSApp.setActivationPolicy(.regular)
        window?.deminiaturize(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if let player = player() { MenuBarLyricsController.shared(for: player).setBackground(false) }
    }
    private func showBackgroundIndicator() {
        guard let player = player() else { return }
        MenuBarLyricsController.shared(for: player).setBackground(true) { [weak self] in self?.restoreWindow() }
    }

}

struct WindowLifecycleAnchor: NSViewRepresentable {
    let appDelegate: AppDelegate
    func makeNSView(context: Context) -> Anchor {
        let view = Anchor()
        view.bind = { [weak appDelegate] window in appDelegate?.bindWindow(window) }
        return view
    }
    func updateNSView(_ view: Anchor, context: Context) { if let window = view.window { appDelegate.bindWindow(window) } }
    final class Anchor: NSView {
        var bind: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if let window { bind?(window) } }
    }
}

@MainActor
enum PlaybackStatusMenu {
    static func make(song: Song?, target: AnyObject, hide: Selector, quit: Selector) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let title = NSMenuItem(title: song.map { "正在播放：\($0.title)" } ?? "未在播放", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        let hideItem = NSMenuItem(title: "隐藏菜单栏歌词", action: hide, keyEquivalent: "")
        hideItem.target = target
        menu.addItem(hideItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "退出", action: quit, keyEquivalent: "")
        quitItem.target = target
        menu.addItem(quitItem)
        return menu
    }
}
