import SwiftUI

/// Match the continuous macOS window contour without masking native window chrome.
enum SurfaceCorners {
    static let window: CGFloat = 20
    static let panel = window
    static let cover = window
    static let row = window
    static func selectionRadius(height: CGFloat) -> CGFloat {
        min(window, max(0, height) * 0.28)
    }
}
