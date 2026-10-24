import SwiftUI

/// Neutral clear glass: no accent-colored fill, with a rounded rectangular outline.
struct TransparentCollectionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .glassEffect(.clear.interactive(), in: .rect(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
