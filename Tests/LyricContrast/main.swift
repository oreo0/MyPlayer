import SwiftUI
import AppKit
func rgb(_ color: Color) -> NSColor { NSColor(color).usingColorSpace(.deviceRGB)! }
func contrast(_ color: NSColor, _ background: Double) -> Double {
    func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
    let front = 0.2126 * linear(color.redComponent) + 0.7152 * linear(color.greenComponent) + 0.0722 * linear(color.blueComponent)
    let back = linear(background)
    return (max(front, back) + 0.05) / (min(front, back) + 0.05)
}
for background in [0.13, 0.32, 0.96] {
    for accent in [Color.blue, .yellow, .white, .red, .green, .teal] {
        precondition(contrast(rgb(LyricContrast.color(accent, background: background)), background) >= 4.499)
    }
}
let adjusted = rgb(LyricContrast.color(.blue, background: 0.96))
precondition(adjusted.blueComponent > adjusted.redComponent)
print("PASS: accent contrast on light/dark backgrounds while preserving blue hue")
