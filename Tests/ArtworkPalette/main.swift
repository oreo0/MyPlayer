import SwiftUI
import AppKit
func rgb(_ color: Color?) -> NSColor { NSColor(color!).usingColorSpace(.deviceRGB)! }
let red = rgb(ArtworkPalette.color(pixels: [220, 20, 20, 255, 255, 255, 255, 255], darkSurface: true))
precondition(red.redComponent > red.greenComponent && red.redComponent > red.blueComponent)
let blue = rgb(ArtworkPalette.color(pixels: [10, 40, 230, 255], darkSurface: false))
precondition(blue.blueComponent > blue.redComponent)
precondition(ArtworkPalette.color(pixels: [0, 0, 0, 0], darkSurface: true) == nil)
precondition(ArtworkPalette.color(pixels: [], darkSurface: true) == nil)
precondition(ArtworkPalette.color(pixels: [255,255,255,255], darkSurface: true) != nil)
print("PASS: cover hues, white margins, transparency and missing cover")
