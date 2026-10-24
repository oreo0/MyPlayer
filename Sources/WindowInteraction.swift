import SwiftUI
import AppKit

/// Tracks the actual window (including its toolbar) without polling or global key capture.
struct WindowInteraction: NSViewRepresentable {
    var hideCursor = false
    var onActivity: () -> Void = {}
    var onCanvasClick: (CGPoint) -> Bool = { _ in false }
    var onFullScreenChange: (Bool) -> Void = { _ in }
    let onChange: (Bool) -> Void
    func makeNSView(context: Context) -> InteractionView {
        let view = InteractionView()
        view.wantsCursorHidden = hideCursor
        view.onCanvasClick = onCanvasClick
        view.onFullScreenChange = onFullScreenChange
        view.onActivity = onActivity
        view.onChange = onChange
        return view
    }
    func updateNSView(_ view: InteractionView, context: Context) { view.wantsCursorHidden = hideCursor; view.applyCursor(); view.onChange = onChange; view.onActivity = onActivity; view.onFullScreenChange = onFullScreenChange; view.onCanvasClick = onCanvasClick }

    static func dismantleNSView(_ view: InteractionView, coordinator: ()) { view.restoreCursor() }
    final class InteractionView: NSView {
        var wantsCursorHidden = false
        private var cursorHidden = false
        func restoreCursor() {
            if cursorHidden { NSCursor.unhide(); cursorHidden = false }
        }
        func applyCursor() {
            let inside = NSApp.isActive && window?.isKeyWindow == true && window?.frame.contains(NSEvent.mouseLocation) == true
            let overPlaybackWindow = !wantsCursorHidden || NSWindow.windowNumber(at: NSEvent.mouseLocation, belowWindowWithWindowNumber: 0) == window?.windowNumber
            if wantsCursorHidden && inside && overPlaybackWindow {
                if !cursorHidden { NSCursor.hide(); cursorHidden = true }
            } else { restoreCursor() }
        }
        var onCanvasClick: ((CGPoint) -> Bool)?
        var onFullScreenChange: ((Bool) -> Void)?
        private var lastFullScreen: Bool?
        var onActivity: (() -> Void)?
        private var lastActivity = Date.distantPast
        var onChange: ((Bool) -> Void)?
        private var localMonitor: Any?
        private var globalMonitor: Any?
        private var observers: [NSObjectProtocol] = []
        private var lastValue: Bool?
        private weak var trackedWindow: NSWindow?
        private var previousMouseMoved = false
        private var tracking: NSTrackingArea?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            guard tracking == nil else { return }
            let area = NSTrackingArea(rect: bounds, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved], owner: self, userInfo: nil)
            addTrackingArea(area)
            tracking = area
        }
        override func mouseEntered(with event: NSEvent) { refresh() }
        override func mouseExited(with event: NSEvent) { refresh() }
        override func mouseMoved(with event: NSEvent) { refresh() }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            cleanUp()
            guard let window else { return }
            window.tabbingMode = .disallowed
            trackedWindow = window
            previousMouseMoved = window.acceptsMouseMovedEvents
            window.acceptsMouseMovedEvents = true
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .mouseEntered, .mouseExited, .leftMouseDown, .leftMouseDragged, .keyDown]) { [weak self] event in
                if event.type == .keyDown,
                   event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock) == .command,
                   let text = event.window?.firstResponder as? NSTextView {
                    switch event.charactersIgnoringModifiers?.lowercased() {
                    case "x": text.cut(nil); return nil
                    case "c": text.copy(nil); return nil
                    case "v": text.paste(nil); return nil
                    default: break
                    }
                }
                if event.type == .leftMouseDown {
                    self?.activityGeneration += 1
                    self?.lastPointerLocation = NSEvent.mouseLocation
                }
                self?.refresh()
                if event.window === self?.window {
                    if event.type == .leftMouseDown, let self, let source = event.window,
                       self.handleCanvasMouseDown(at: event.locationInWindow, in: source) { return nil }
                    if event.type == .mouseMoved || event.type == .leftMouseDragged {
                        self?.registerPointerMotion(at: NSEvent.mouseLocation)
                    }
                }
                return event
            }
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in self?.refresh() }
            for name in [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification, NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification, NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.refresh() }
                })
            }
            refresh()
        }
        /// Use the window's mouse-down stream, not SwiftUI's cached hover hit graph.
        /// A full-size content view may extend behind the toolbar, so use the
        /// content layout rectangle to leave native toolbar buttons untouched.
        func handleCanvasMouseDown(at point: NSPoint, in sourceWindow: NSWindow) -> Bool {
            guard let window, sourceWindow === window,
                  point.y < window.contentLayoutRect.maxY,
                  !CanvasClickPassthrough.contains(point, in: window) else { return false }
            return onCanvasClick?(point) == true
        }
        @discardableResult func registerPointerMotion(at location: NSPoint) -> Bool {
            guard lastPointerLocation != location else { return false }
            lastPointerLocation = location
            let wasHidden = wantsCursorHidden
            wantsCursorHidden = false
            restoreCursor()
            reportActivity(force: wasHidden)
            return true
        }
        private var lastPointerLocation: NSPoint?
        private var activityGeneration = 0
        private func reportActivity(force: Bool = false) {
            guard force || Date().timeIntervalSince(lastActivity) > 0.15 else { return }
            lastActivity = Date()
            let generation = activityGeneration
            DispatchQueue.main.async { [weak self] in
                guard let self, self.activityGeneration == generation else { return }
                self.onActivity?()
            }
        }
        private func refresh() {
            applyCursor()
            let fullScreen = window?.styleMask.contains(.fullScreen) == true
            if lastFullScreen != fullScreen {
                lastFullScreen = fullScreen
                DispatchQueue.main.async { [weak self] in self?.onFullScreenChange?(fullScreen) }
            }
            let value = NSApp.isActive && window?.isKeyWindow == true && window?.frame.contains(NSEvent.mouseLocation) == true
            guard lastValue != value else { return }
            lastValue = value
            DispatchQueue.main.async { [weak self] in self?.onChange?(value) }
        }
        private func cleanUp() {
            restoreCursor()
            trackedWindow?.acceptsMouseMovedEvents = previousMouseMoved
            trackedWindow = nil
            if let localMonitor { NSEvent.removeMonitor(localMonitor) }
            if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
            localMonitor = nil; globalMonitor = nil
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
        }
        deinit {
            if let localMonitor { NSEvent.removeMonitor(localMonitor) }
            if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
            observers.forEach(NotificationCenter.default.removeObserver)
        }
    }
}
