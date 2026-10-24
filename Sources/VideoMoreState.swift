import Foundation

/// Hover opens temporarily; clicking pins until the next click.
struct VideoMoreState: Equatable {
    enum Source { case closed, hover, pinned }
    private(set) var source: Source = .closed
    var isExpanded: Bool { source != .closed }
    mutating func hoverMore() { if source == .closed { source = .hover } }
    mutating func clickMore() { source = source == .pinned ? .closed : .pinned }
    mutating func leavePanel(popupOpen: Bool) { if source == .hover && !popupOpen { source = .closed } }
    mutating func popupClosed(pointerInside: Bool) { if !pointerInside { leavePanel(popupOpen: false) } }
    mutating func hidePanel() { leavePanel(popupOpen: false) }
}
