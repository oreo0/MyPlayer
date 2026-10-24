import SwiftUI
import AppKit

/// Marks interactive lyric rows so the window's canvas monitor leaves their
/// mouse events to SwiftUI. Weak entries expire as lazy rows leave the tree.
struct CanvasClickPassthrough: NSViewRepresentable {
    var enabled: Bool
    private static let anchors = NSHashTable<Anchor>.weakObjects()
    func makeNSView(context: Context) -> Anchor {
        let view = Anchor()
        view.enabled = enabled
        Self.anchors.add(view)
        return view
    }
    func updateNSView(_ view: Anchor, context: Context) { view.enabled = enabled }
    static func contains(_ point: CGPoint, in window: NSWindow) -> Bool {
        regions(in: window).contains { $0.contains(point) }
    }
    static func regions(in window: NSWindow) -> [CGRect] {
        anchors.allObjects.compactMap { view in
            guard view.enabled, view.window === window, !view.isHiddenOrHasHiddenAncestor,
                  !view.visibleRect.isEmpty else { return nil }
            var ancestor: NSView? = view
            while let current = ancestor {
                if current.alphaValue <= 0.01 { return nil }
                ancestor = current.superview
            }
            // macOS 26+ unclipped NSViews can report a visibleRect extending
            // beyond their bounds. Exclusions must never include that overflow.
            let region = view.visibleRect.intersection(view.bounds)
            guard !region.isNull, !region.isEmpty else { return nil }
            return view.convert(region, to: nil)
        }
    }
    final class Anchor: NSView {
        var enabled = true
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
