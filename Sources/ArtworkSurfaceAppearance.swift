import SwiftUI
import AppKit

@MainActor final class ArtworkSurfaceAppearance: ObservableObject {
    @Published private(set) var scheme: ColorScheme = .dark
    @Published private(set) var accent: Color?
    @Published private(set) var ambientColors: [Color] = []
    func update(_ data: Data?, fallback: ColorScheme) async {
        guard let data else { scheme = fallback; accent = nil; ambientColors = []; return }
        let sample = await Task.detached(priority: .utility) { () -> ([UInt8], Double)? in
            guard let image = ArtworkRendering.thumbnail(data, maximum: 32) else { return nil }
            var pixels = [UInt8](repeating: 0, count: 16 * 16 * 4)
            let valid = pixels.withUnsafeMutableBytes { buffer -> Bool in
                guard let context = CGContext(data: buffer.baseAddress, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 64, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                context.draw(image, in: CGRect(x: 0, y: 0, width: 16, height: 16)); return true
            }
            guard valid else { return nil }
            var brightness = 0.0
            for i in stride(from: 0, to: pixels.count, by: 4) { brightness += 0.2126 * Double(pixels[i]) + 0.7152 * Double(pixels[i + 1]) + 0.0722 * Double(pixels[i + 2]) }
            return (pixels, brightness / (256 * 255))
        }.value
        guard !Task.isCancelled else { return }
        guard let sample else { scheme = fallback; accent = nil; ambientColors = []; return }
        scheme = sample.1 > 0.58 ? .light : .dark
        ambientColors = ArtworkPalette.ambientColors(pixels: sample.0)
        accent = ArtworkPalette.color(pixels: sample.0, darkSurface: scheme == .dark)
    }
}
