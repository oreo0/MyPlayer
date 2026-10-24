import AppKit
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1800, pixelsHigh: 900, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 7200, bitsPerPixel: 32)!
memset(bitmap.bitmapData!, 180, bitmap.bytesPerRow * bitmap.pixelsHigh)
let data = bitmap.representation(using: .png, properties: [:])!
let thumbnail = ArtworkRendering.thumbnail(data, maximum: 512)!
precondition(thumbnail.width == 512 && thumbnail.height == 256)
let backdrop = ArtworkRendering.backdrop(data)!
precondition(backdrop.width <= 128 && backdrop.height <= 128)
precondition(ArtworkRendering.thumbnail(Data(), maximum: 128) == nil)
print("PASS: bounded artwork decoding, preserved aspect ratio, cached-size backdrop and invalid input")
