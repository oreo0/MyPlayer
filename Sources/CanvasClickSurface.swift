import SwiftUI
import AppKit

/// Receives empty-canvas clicks directly, without intercepting native control events.
struct CanvasClickSurface: NSViewRepresentable {
    var shouldCapture: (CGPoint) -> Bool
    var onClick: (CGPoint) -> Void
    func makeNSView(context: Context) -> Surface { let view = Surface(); update(view); return view }
    func updateNSView(_ view: Surface, context: Context) { update(view) }
    private func update(_ view: Surface) { view.shouldCapture = shouldCapture; view.onClick = onClick }
    final class Surface: NSView {
        var shouldCapture: (CGPoint) -> Bool = { _ in true }
        var onClick: (CGPoint) -> Void = { _ in }
        override var acceptsFirstResponder: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? {
            if let event = NSApp.currentEvent, event.type != .leftMouseDown { return nil }
            let local = convert(point, from: superview)
            guard bounds.contains(local), let window else { return nil }
            let position = convert(local, to: nil)
            guard shouldCapture(position), !CanvasClickPassthrough.contains(position, in: window) else { return nil }
            return self
        }
        override func mouseDown(with event: NSEvent) { onClick(event.locationInWindow) }
    }
}
