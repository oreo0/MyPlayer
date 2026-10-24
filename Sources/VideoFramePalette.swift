import CoreVideo
import Foundation

/// Sparse decoded-frame samples in RGBA order; shared by contrast and accent.
enum VideoFramePalette {
    struct Sample { let pixels: [UInt8]; let brightness: Double }
    static func sample(_ frame: CVPixelBuffer) -> Sample? {
        let format = CVPixelBufferGetPixelFormatType(frame)
        if format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange || format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange {
            return sampleBiPlanar(frame, fullRange: format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
        }
        guard format == kCVPixelFormatType_32BGRA else { return nil }
        CVPixelBufferLockBaseAddress(frame, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(frame, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(frame) else { return nil }
        let width = CVPixelBufferGetWidth(frame), height = CVPixelBufferGetHeight(frame)
        guard width > 0, height > 0 else { return nil }
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        let rowBytes = CVPixelBufferGetBytesPerRow(frame)
        var pixels: [UInt8] = []
        var sum = 0.0
        for y in stride(from: 0, to: height, by: max(1, height / 18)) {
            for x in stride(from: 0, to: width, by: max(1, width / 32)) {
                let offset = y * rowBytes + x * 4
                let b = bytes[offset], g = bytes[offset + 1], r = bytes[offset + 2]
                pixels.append(contentsOf: [r, g, b, 255])
                sum += 0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)
            }
        }
        return Sample(pixels: pixels, brightness: sum / (Double(pixels.count / 4) * 255))
    }
    private static func sampleBiPlanar(_ frame: CVPixelBuffer, fullRange: Bool) -> Sample? {
        guard CVPixelBufferGetPlaneCount(frame) == 2 else { return nil }
        CVPixelBufferLockBaseAddress(frame, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(frame, .readOnly) }
        guard let luma = CVPixelBufferGetBaseAddressOfPlane(frame, 0)?.assumingMemoryBound(to: UInt8.self),
              let chroma = CVPixelBufferGetBaseAddressOfPlane(frame, 1)?.assumingMemoryBound(to: UInt8.self) else { return nil }
        let width = CVPixelBufferGetWidthOfPlane(frame, 0), height = CVPixelBufferGetHeightOfPlane(frame, 0)
        let yStride = CVPixelBufferGetBytesPerRowOfPlane(frame, 0), uvStride = CVPixelBufferGetBytesPerRowOfPlane(frame, 1)
        guard width > 0, height > 0 else { return nil }
        var pixels: [UInt8] = []; pixels.reserveCapacity(32 * 20 * 4)
        var sum = 0.0
        func byte(_ value: Double) -> UInt8 { UInt8(max(0, min(255, value.rounded()))) }
        for y in stride(from: 0, to: height, by: max(1, height / 18)) {
            for x in stride(from: 0, to: width, by: max(1, width / 32)) {
                let yy = Double(luma[y * yStride + x])
                let index = (y / 2) * uvStride + (x / 2) * 2
                let u = Double(chroma[index]) - 128, v = Double(chroma[index + 1]) - 128
                let level = fullRange ? yy : (yy - 16) * 255 / 219
                let r = byte(level + (fullRange ? 1.5748 : 1.7927) * v)
                let g = byte(level - (fullRange ? 0.1873 : 0.2132) * u - (fullRange ? 0.4681 : 0.5329) * v)
                let b = byte(level + (fullRange ? 1.8556 : 2.1124) * u)
                pixels.append(contentsOf: [r, g, b, 255])
                sum += 0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)
            }
        }
        return Sample(pixels: pixels, brightness: sum / (Double(pixels.count / 4) * 255))
    }

}
