import AppKit
import Combine

/// Window events pause only the background; no layout state is written per frame.
@MainActor final class BetaRenderingActivity: ObservableObject {
    static let shared = BetaRenderingActivity()
    @Published private(set) var canAnimate = false
    private var tokens: [NSObjectProtocol] = []
    private var resizing = false
    private init() {
        let center = NotificationCenter.default
        for name in [NSWindow.willStartLiveResizeNotification, NSWindow.didEndLiveResizeNotification,
                     NSWindow.didChangeOcclusionStateNotification, NSApplication.didBecomeActiveNotification,
                     NSApplication.didResignActiveNotification, Notification.Name.NSProcessInfoPowerStateDidChange] {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if notification.name == NSWindow.willStartLiveResizeNotification { self.resizing = true }
                    if notification.name == NSWindow.didEndLiveResizeNotification { self.resizing = false }
                    self.refresh()
                }
            })
        }
        refresh()
    }
    private func refresh() {
        let visible = NSApp.windows.contains { $0.isVisible && !$0.isMiniaturized && $0.occlusionState.contains(.visible) }
        let value = NSApp.isActive && visible && !resizing && !ProcessInfo.processInfo.isLowPowerModeEnabled
        if value != canAnimate { canAnimate = value }
    }
}
