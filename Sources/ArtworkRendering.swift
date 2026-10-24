import AppKit
import ImageIO
import Accelerate

/// Decode bounded images, and blur a small source once instead of every frame.
enum ArtworkRendering {
    static func thumbnail(_ data: Data, maximum: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: maximum, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary)
    }
    static func backdrop(_ data: Data) -> CGImage? {
        guard let image = thumbnail(data, maximum: 128) else { return nil }
        let width = image.width, height = image.height, rowBytes = width * 4
        var source = [UInt8](repeating: 0, count: rowBytes * height)
        var destination = source
        return source.withUnsafeMutableBytes { input in
            destination.withUnsafeMutableBytes { output in
                let space = CGColorSpaceCreateDeviceRGB()
                let info = CGImageAlphaInfo.premultipliedLast.rawValue
                guard let context = CGContext(data: input.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: rowBytes, space: space, bitmapInfo: info) else { return nil }
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                var a = vImage_Buffer(data: input.baseAddress!, height: UInt(height), width: UInt(width), rowBytes: rowBytes)
                var b = vImage_Buffer(data: output.baseAddress!, height: UInt(height), width: UInt(width), rowBytes: rowBytes)
                let limit = min(17, min(width, height))
                let kernel = UInt32(limit % 2 == 0 ? max(1, limit - 1) : limit)
                // Three small box passes approximate a Gaussian, once per cover.
                for _ in 0..<3 {
                    guard vImageBoxConvolve_ARGB8888(&a, &b, nil, 0, 0, kernel, kernel, nil, vImage_Flags(kvImageEdgeExtend)) == kvImageNoError else { return nil }
                    swap(&a, &b)
                }
                let data = Data(bytes: a.data, count: rowBytes * height)
                guard let provider = CGDataProvider(data: data as CFData) else { return nil }
                return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: rowBytes, space: space, bitmapInfo: CGBitmapInfo(rawValue: info), provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
            }
        }
    }
    static func native(_ image: CGImage) -> NSImage {
        NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}
