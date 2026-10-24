import SwiftUI

struct WithinWindowBlur: View {
    var atTop = false
    var radius: CGFloat = 36
    var body: some View {
        Rectangle().fill(.regularMaterial)
            .mask(LinearGradient(colors: [.clear, .black], startPoint: atTop ? .top : .bottom, endPoint: atTop ? .bottom : .top))
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}
