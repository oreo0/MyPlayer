import SwiftUI
import AppKit

/// App-local event monitor: never captures global keys or typing in text fields.
struct SeekKeyboard: NSViewRepresentable {
    let player: PlayerManager
    func makeCoordinator() -> Coordinator { Coordinator(player) }
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.view = view
        return view
    }
    func updateNSView(_ view: NSView, context: Context) { }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) { coordinator.remove() }
    final class Coordinator {
        weak var view: NSView?
        let player: PlayerManager
        var monitor: Any?
        init(_ player: PlayerManager) {
            self.player = player
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, event.window === self.view?.window,
                      MainActor.assumeIsolated({ PlaybackKeyboardScope.permitsTransport(in: event.window) }) else { return event }
                let handled = MainActor.assumeIsolated {
                    guard self.player.nowPlaying != nil else { return false }
                    let store = ShortcutStore.shared
                    let direction: Double
                    if store.binding(.seekBack).matches(event) { direction = -5 }
                    else if store.binding(.seekForward).matches(event) { direction = 5 }
                    else { return false }
                    self.player.seek(to: self.player.currentTime + direction)
                    return true
                }
                return handled ? nil : event
            }
        }
        func remove() { if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil } }
        deinit { remove() }
    }
}
