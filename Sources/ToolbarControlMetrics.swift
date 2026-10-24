import SwiftUI

/// Scoped to the right-hand toolbar strips. No inherited control sizing from
/// the window, native toolbar grouping, or player bar changes these metrics.
enum ToolbarControlMetrics {
    static let size: CGFloat = 32
    static let iconSize: CGFloat = 14
}
/// Retain AppKit/SwiftUI's native tint and disabled-state rendering, while
/// fixing only the layout slot. No replacement pressed/selected color logic.
struct ToolbarIconButton<IconLabel: View>: View {
    private let action: () -> Void
    private let iconLabel: IconLabel
    init(action: @escaping () -> Void, @ViewBuilder label: () -> IconLabel) {
        self.action = action; iconLabel = label()
    }
    init(_ title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void)
        where IconLabel == Label<Text, Image> {
        self.action = action; iconLabel = Label(title, systemImage: systemImage)
    }
    var body: some View {
        Button(action: action) { iconLabel }
            .buttonStyle(.borderless)
            .frame(width: ToolbarControlMetrics.size, height: ToolbarControlMetrics.size)
    }
}
