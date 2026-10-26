import SwiftUI
import AppKit

/// Read the native toolbar exclusion once per layout change, not on a display timer.
struct WindowContentTopInset: NSViewRepresentable {
    let update: (CGFloat) -> Void
    func makeNSView(context: Context) -> Anchor { let view = Anchor(); view.update = update; return view }
    func updateNSView(_ view: Anchor, context: Context) { view.update = update; view.schedule() }
    static func dismantleNSView(_ view: Anchor, coordinator: ()) { view.detach() }
    final class Anchor: NSView {
        var update: ((CGFloat) -> Void)?
        private var tokens: [NSObjectProtocol] = []
        private var pending = false
        private var last: CGFloat?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow(); detach()
            guard let window else { return }
            for name in [NSWindow.didResizeNotification, NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification] {
                tokens.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.schedule() } })
            }
            schedule()
        }
        func schedule() {
            guard !pending else { return }; pending = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }; self.pending = false
                guard let window = self.window else { return }
                let inset = max(0, window.frame.height - window.contentLayoutRect.maxY)
                guard self.last != inset else { return }; self.last = inset; self.update?(inset)
            }
        }
        func detach() { tokens.forEach(NotificationCenter.default.removeObserver); tokens.removeAll() }
        deinit { tokens.forEach(NotificationCenter.default.removeObserver) }
    }
}
