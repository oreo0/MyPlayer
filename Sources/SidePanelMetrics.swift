import Foundation

/// Keep sizing consistent between retained library panels, overlays and hit testing.
enum SidePanelMetrics {
    static func inlineWidth(for windowWidth: CGFloat) -> CGFloat {
        min(495, max(240, windowWidth - 450)) * 0.75
    }
    static func overlayWidth(for windowWidth: CGFloat) -> CGFloat {
        min(570, windowWidth * 0.60) * 0.75
    }
    static func limits(for width: CGFloat, overlay: Bool) -> ClosedRange<CGFloat> {
        let maximum = max(180, min(720, width - (overlay ? 80 : 450)))
        return min(240, maximum)...maximum
    }
    static func resolvedWidth(for width: CGFloat, preferred: CGFloat, overlay: Bool) -> CGFloat {
        let value = preferred > 0 ? preferred : (overlay ? overlayWidth(for: width) : inlineWidth(for: width))
        let range = limits(for: width, overlay: overlay)
        return min(range.upperBound, max(range.lowerBound, value))
    }
}
