import SwiftUI

/// Quantized dominant color, favouring visible chroma over white/black margins.
enum ArtworkPalette {
    /// Several dominant cover colors, with neutral borders excluded.
    static func ambientColors(pixels: [UInt8]) -> [Color] {
        guard pixels.count >= 4 else { return [] }
        var bins = [Int: (r: Double, g: Double, b: Double, count: Double)]()
        for i in stride(from: 0, through: pixels.count - 4, by: 4) where pixels[i + 3] > 128 {
            let r = Double(pixels[i]) / 255, g = Double(pixels[i + 1]) / 255, b = Double(pixels[i + 2]) / 255
            let hi = max(r, g, b), lo = min(r, g, b)
            guard hi > 0.08, lo < 0.94 else { continue }
            let key = Int(pixels[i] >> 6) * 16 + Int(pixels[i + 1] >> 6) * 4 + Int(pixels[i + 2] >> 6)
            let old = bins[key] ?? (0, 0, 0, 0)
            bins[key] = (old.r + r, old.g + g, old.b + b, old.count + 1)
        }
        return bins.sorted { a, b in a.value.count == b.value.count ? a.key < b.key : a.value.count > b.value.count }
            .prefix(4).map { item in
                let v = item.value
                return Color(red: v.r / v.count, green: v.g / v.count, blue: v.b / v.count)
            }
    }

    static func color(pixels: [UInt8], darkSurface: Bool) -> Color? {
        guard pixels.count >= 4 else { return nil }
        var buckets: [Int: (Double, Double, Double, Double)] = [:]
        var fallback = (0.0, 0.0, 0.0, 0.0)
        for index in stride(from: 0, through: pixels.count - 4, by: 4) {
            guard pixels[index + 3] > 128 else { continue }
            let r = Double(pixels[index]) / 255, g = Double(pixels[index + 1]) / 255, b = Double(pixels[index + 2]) / 255
            fallback.0 += r; fallback.1 += g; fallback.2 += b; fallback.3 += 1
            let maximum = max(r, g, b), minimum = min(r, g, b)
            guard maximum > 0.1, minimum < 0.92 else { continue }
            let weight = 0.2 + maximum - minimum
            let key = Int(pixels[index] >> 5) * 64 + Int(pixels[index + 1] >> 5) * 8 + Int(pixels[index + 2] >> 5)
            let old = buckets[key] ?? (0, 0, 0, 0)
            buckets[key] = (old.0 + r * weight, old.1 + g * weight, old.2 + b * weight, old.3 + weight)
        }
        guard fallback.3 > 0 else { return nil }
        let chosen = buckets.values.max { $0.3 < $1.3 } ?? fallback
        var r = chosen.0 / chosen.3, g = chosen.1 / chosen.3, b = chosen.2 / chosen.3
        let brightness = 0.2126 * r + 0.7152 * g + 0.0722 * b
        if darkSurface && brightness < 0.62 {
            let lift = (0.62 - brightness) / max(0.01, 1 - brightness)
            r += (1 - r) * lift; g += (1 - g) * lift; b += (1 - b) * lift
        } else if !darkSurface && brightness > 0.4 {
            let scale = 0.4 / brightness
            r *= scale; g *= scale; b *= scale
        }
        return Color(red: r, green: g, blue: b)
    }
}
private struct PlaybackAccentKey: EnvironmentKey { static let defaultValue: Color? = nil }
extension EnvironmentValues {
    var playbackAccent: Color? {
        get { self[PlaybackAccentKey.self] }
        set { self[PlaybackAccentKey.self] = newValue }
    }
}
