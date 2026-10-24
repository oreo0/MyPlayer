import SwiftUI
import AppKit

/// Adjust only as far as necessary, preserving the accent's hue instead of
/// replacing it with the same primary color used by inactive lyric lines.
enum LyricContrast {
    static func color(_ accent: Color, background: Double) -> Color {
        guard let color = NSColor(accent).usingColorSpace(.deviceRGB) else { return .primary }
        let original = [Double(color.redComponent), Double(color.greenComponent), Double(color.blueComponent)]
        func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let back = linear(background)
        func ratio(_ rgb: [Double]) -> Double {
            let luminance = 0.2126 * linear(rgb[0]) + 0.7152 * linear(rgb[1]) + 0.0722 * linear(rgb[2])
            return (max(luminance, back) + 0.05) / (min(luminance, back) + 0.05)
        }
        if ratio(original) >= 4.5 { return accent }
        let target = back > 0.18 ? 0.0 : 1.0
        var low = 0.0, high = 1.0
        for _ in 0..<20 {
            let amount = (low + high) / 2
            let candidate = original.map { $0 + (target - $0) * amount }
            if ratio(candidate) >= 4.5 { high = amount } else { low = amount }
        }
        let result = original.map { $0 + (target - $0) * high }
        return Color(red: result[0], green: result[1], blue: result[2])
    }
}
