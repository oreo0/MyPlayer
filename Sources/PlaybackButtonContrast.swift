import Foundation

enum PlaybackButtonContrast {
    static func luminance(_ red: Double, _ green: Double, _ blue: Double) -> Double {
        func linear(_ x: Double) -> Double { x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
    static func usesBlack(_ red: Double, _ green: Double, _ blue: Double) -> Bool {
        luminance(red, green, blue) > sqrt(0.0525) - 0.05
    }
}
