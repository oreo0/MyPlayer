import SwiftUI

struct PlaybackActivationStyle: ViewModifier {
    let active: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.playbackAccent) private var playbackAccent
    @ViewBuilder func body(content: Content) -> some View {
        if active { content.buttonStyle(.glassProminent).tint(playbackAccent ?? ThemeColor.current.color ?? .accentColor).buttonBorderShape(.circle) }
        else { content.buttonStyle(.glass).tint(scheme == .dark ? Color(white: 0.24) : Color(white: 0.88)).buttonBorderShape(.circle) }
    }
}
