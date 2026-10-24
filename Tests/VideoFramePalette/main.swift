import CoreVideo
import SwiftUI
import AppKit

func frame(r: UInt8, g: UInt8, b: UInt8) -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    precondition(CVPixelBufferCreate(nil, 70, 43, kCVPixelFormatType_32BGRA, nil, &buffer) == kCVReturnSuccess)
    let result = buffer!
    CVPixelBufferLockBaseAddress(result, [])
    let bytes = CVPixelBufferGetBaseAddress(result)!.assumingMemoryBound(to: UInt8.self)
    let pitch = CVPixelBufferGetBytesPerRow(result)
    for y in 0..<43 {
        for x in 0..<70 {
            let i = y * pitch + x * 4
            bytes[i] = b; bytes[i + 1] = g; bytes[i + 2] = r; bytes[i + 3] = 255
        }
    }
    CVPixelBufferUnlockBaseAddress(result, [])
    return result
}
for (r, g, b, expected) in [(UInt8(255), UInt8(0), UInt8(0), 0.2126), (0, 255, 0, 0.7152), (0, 0, 255, 0.0722), (255, 255, 255, 1.0), (0, 0, 0, 0.0)] {
    let sample = VideoFramePalette.sample(frame(r: r, g: g, b: b))!
    precondition(Array(sample.pixels.prefix(4)) == [r, g, b, 255])
    precondition(abs(sample.brightness - expected) < 0.000001)
    precondition(sample.pixels.count < 70 * 43 * 4)
    let color = NSColor(ArtworkPalette.color(pixels: sample.pixels, darkSurface: true)!).usingColorSpace(.deviceRGB)!
    if r > g && r > b { precondition(color.redComponent > color.greenComponent && color.redComponent > color.blueComponent) }
    if g > r && g > b { precondition(color.greenComponent > color.redComponent && color.greenComponent > color.blueComponent) }
    if b > r && b > g { precondition(color.blueComponent > color.redComponent && color.blueComponent > color.greenComponent) }
}
print("PASS: video BGRA channel conversion, row stride, sparse sampling, brightness and live accent hue")
