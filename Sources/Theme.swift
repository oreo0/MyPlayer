import SwiftUI

// MARK: - 主题色（设置 → 外观）

enum ThemeColor: String, CaseIterable, Identifiable {
    case system
    case media
    case teal
    case blue
    case indigo
    case pink
    case orange
    case mint
    case white, yellow, lightBlue, red, green

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "跟随系统"
        case .media: return "跟随文件或视频"
        case .teal: return "青色"
        case .blue: return "蓝色"
        case .indigo: return "紫色"
        case .pink: return "粉色"
        case .orange: return "橙色"
        case .mint: return "薄荷绿"
        case .white: return "白色"
        case .yellow: return "黄色"
        case .lightBlue: return "淡蓝色"
        case .red: return "红色"
        case .green: return "绿色"
        }
    }

    var color: Color? {
        switch self {
        case .system, .media: return nil
        case .teal: return Color.teal
        case .blue: return Color.blue
        case .indigo: return Color.indigo
        case .pink: return Color.pink
        case .orange: return Color.orange
        case .mint: return Color.mint
        case .white: return .white
        case .yellow: return .yellow
        case .lightBlue: return Color(red: 0.5, green: 0.76, blue: 1)
        case .red: return .red
        case .green: return .green
        }
    }

    static var current: ThemeColor {
        ThemeColor(rawValue: UserDefaults.standard.string(forKey: "themeColorName") ?? "") ?? .system
    }
}

enum LyricsWeight: String, CaseIterable, Identifiable {
    case light, regular, medium, semibold, bold, heavy
    var id: String { rawValue }
    var label: String {
        switch self { case .light: "细体"; case .regular: "常规"; case .medium: "中等"; case .semibold: "半粗"; case .bold: "粗体"; case .heavy: "特粗" }
    }
    var weight: Font.Weight {
        switch self { case .light: .light; case .regular: .regular; case .medium: .medium; case .semibold: .semibold; case .bold: .bold; case .heavy: .heavy }
    }
}

// Native glass is reserved for floating controls; content stays legible.
struct BetaGlassSurface: ViewModifier {
    var radius: CGFloat = SurfaceCorners.panel
    var clear = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(nsColor: .windowBackgroundColor), in: .rect(cornerRadius: radius))
        } else {
            content.glassEffect(clear ? .clear : .regular, in: .rect(cornerRadius: radius))
        }
    }
}

/// Draw a small mesh and let the compositor upscale it; never blur a full window.
struct BetaAmbientLight: View {
    var colors: [Color]
    var playing: Bool
    var immersive = false
    @AppStorage("betaVisualStyle") private var style = "aurora"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.scenePhase) private var phase
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var activity = BetaRenderingActivity.shared
    private var animates: Bool {
        playing && !reduceMotion && phase == .active && activity.canAnimate && style == "aurora"
    }
    var body: some View {
        if style != "off" && !reduceTransparency && !colors.isEmpty {
            GeometryReader { proxy in
                TimelineView(.animation(minimumInterval: 1.0 / 15, paused: !animates)) { context in
                    let t = animates ? context.date.timeIntervalSinceReferenceDate * 0.10 : 0
                    MeshGradient(width: 3, height: 3, points: [
                        [0, 0], [0.5, 0], [1, 0],
                        [0, 0.5], [Float(0.5 + 0.20 * sin(t)), Float(0.5 + 0.18 * cos(t * 0.8))], [1, 0.5],
                        [0, 1], [0.5, 1], [1, 1]
                    ], colors: (0..<9).map { index in colors[(index + (index / 3)) % colors.count] }, smoothsColors: true)
                    .frame(width: 160, height: 160)
                    .drawingGroup(opaque: true)
                    .scaleEffect(x: max(1, proxy.size.width) / 160, y: max(1, proxy.size.height) / 160)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                }
                .opacity(immersive ? 0.95 : (scheme == .dark ? 0.42 : 0.22))
            }
            .clipped().allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}

struct BetaArtworkDepth: ViewModifier {
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .scaleEffect(hovered && !reduceMotion ? 1.012 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.8), value: hovered)
            .onHover { hovered = $0 }
    }
}

private struct AmbientArtworkColorsKey: EnvironmentKey { static let defaultValue: [Color] = [] }
extension EnvironmentValues {
    var ambientArtworkColors: [Color] {
        get { self[AmbientArtworkColorsKey.self] }
        set { self[AmbientArtworkColorsKey.self] = newValue }
    }
}
