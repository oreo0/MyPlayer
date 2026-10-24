import Foundation
import SwiftUI
import AppKit
struct Song { let artworkData: Data? }
@main struct AppearanceChecks {
    @MainActor static func main() async {
        precondition(ApplicationAppearance.resolve(mode: "light", systemIsDark: true) == .light)
        precondition(ApplicationAppearance.resolve(mode: "dark", systemIsDark: false) == .dark)
        precondition(ApplicationAppearance.resolve(mode: "system", systemIsDark: false) == .light)
        precondition(ApplicationAppearance.resolve(mode: "system", systemIsDark: true) == .dark)
        func fixture(_ value: CGFloat) -> Song {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 32, bitsPerPixel: 32)!
            let pixels = bitmap.bitmapData!
            for offset in stride(from: 0, to: 8 * 8 * 4, by: 4) {
                pixels[offset] = UInt8(value * 255); pixels[offset + 1] = UInt8(value * 255)
                pixels[offset + 2] = UInt8(value * 255); pixels[offset + 3] = 255
            }
            return Song(artworkData: bitmap.representation(using: .png, properties: [:])!)
        }
        let appearance = PlaybackAppearance()
        await appearance.observe(song: fixture(1), video: nil, active: true, darkLyrics: false)
        precondition(appearance.scheme == .light)
        await appearance.observe(song: fixture(0), video: nil, active: true, darkLyrics: false)
        precondition(appearance.scheme == .dark)
        // A dark playback palette must not change the library's light baseline.
        precondition(ApplicationAppearance.resolve(mode: "light", systemIsDark: true) == .light)
        precondition(ApplicationAppearance.resolve(mode: "system", systemIsDark: false) == .light)
        await appearance.observe(song: fixture(1), video: nil, active: true, darkLyrics: true)
        precondition(appearance.scheme == .dark)
        await appearance.observe(song: nil, video: nil, active: true, darkLyrics: false)
        precondition(appearance.scheme == .dark)
        await appearance.observe(song: fixture(0), video: nil, active: true, darkLyrics: false, defaultScheme: .light)
        precondition(appearance.scheme == .light)
        await appearance.observe(song: fixture(1), video: nil, active: true, darkLyrics: false, defaultScheme: .dark)
        precondition(appearance.scheme == .dark)
        print("PASS: cover brightness, lyric backdrop, missing cover and default light/dark surfaces")
    }
}
