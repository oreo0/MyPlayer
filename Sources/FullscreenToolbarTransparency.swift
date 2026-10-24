import SwiftUI
import AppKit

/// Clear only the system titlebar's visual-effect backdrop, preserving its
/// controls and original mask. Runs on presentation transitions, never per frame.
struct FullscreenToolbarTransparency: NSViewRepresentable {
    let enabled: Bool
    func makeNSView(context: Context) -> Anchor { Anchor() }
    func updateNSView(_ view: Anchor, context: Context) { view.setEnabled(enabled) }
    static func dismantleNSView(_ view: Anchor, coordinator: ()) { view.restore() }
    final class Anchor: NSView {
        private var enabled = false
        private var observers: [NSObjectProtocol] = []
        private var scheduled: DispatchWorkItem?
        private var masks: [(view: NSVisualEffectView, image: NSImage?)] = []
        private static let transparentMask: NSImage = {
            let image = NSImage(size: NSSize(width: 1, height: 1))
            image.lockFocus()
            NSColor.clear.setFill()
            NSRect(x: 0, y: 0, width: 1, height: 1).fill(using: .copy)
            image.unlockFocus()
            return image
        }()
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach { NotificationCenter.default.removeObserver($0) }; observers.removeAll()
            if let window {
                for name in [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification] {
                    observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated { if self?.enabled == true { self?.schedule() } }
                    })
                }
            }
            if enabled { schedule() }
        }
        deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }
        func setEnabled(_ value: Bool) {
            guard enabled != value else { return }
            enabled = value
            if value { schedule() } else { restore() }
        }
        private func schedule() {
            scheduled?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.apply() }
            scheduled = work
            // Fullscreen moves the native titlebar into its presentation host.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        }
        private func apply() {
            guard enabled, let window,
                  let content = window.contentView else { return }
            var roots: [NSView] = []
            if let root = content.superview { roots.append(root) }
            // Fullscreen may host the titlebar outside the content's theme frame.
            // Resolve the app's own titlebar through its public window controls.
            if var root = window.standardWindowButton(.closeButton)?.superview {
                while let parent = root.superview { root = parent }
                if !roots.contains(where: { $0 === root }) { roots.append(root) }
            }
            for root in roots { clearBackdrop(in: root, excluding: content) }
        }

        func clearBackdrop(in root: NSView, excluding content: NSView) {
            func visit(_ view: NSView) {
                guard view !== content else { return }
                if let effect = view as? NSVisualEffectView,
                   !masks.contains(where: { $0.view === effect }) {
                    masks.append((effect, effect.maskImage))
                    // NSVisualEffectView's mask affects its material, not its controls.
                    effect.maskImage = Self.transparentMask
                }
                for child in view.subviews { visit(child) }
            }
            visit(root)
        }
        func restore() {
            scheduled?.cancel(); scheduled = nil
            for entry in masks { entry.view.maskImage = entry.image }
            masks.removeAll()
        }
    }
}
