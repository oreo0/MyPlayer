import SwiftUI

/// Diffuse only scrolling row content as it enters the heading. The window's
/// existing backdrop is never painted over, so all backdrop styles and both
/// appearances retain exactly the same background behind the titles.
struct CollectionHeaderBlur: ViewModifier {
    nonisolated static let coordinateSpace = "collections.viewport"
    nonisolated static let headingInset: CGFloat = 96
    func body(content: Content) -> some View {
        content.visualEffect { effect, geometry in
            effect.blur(radius: Self.radius(rowTop: geometry.frame(in: .named(Self.coordinateSpace)).minY))
        }
    }
    nonisolated static func radius(rowTop: CGFloat) -> CGFloat {
        min(18, max(0, (headingInset - rowTop) * 0.5))
    }
}
