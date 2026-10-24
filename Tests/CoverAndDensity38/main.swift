import Foundation
import AppKit

@main struct CoverAndDensityTests {
    @MainActor static func main() {
        let table = NSTableView(frame: CGRect(x: 0, y: 0, width: 800, height: 500))
        let density = NativeTableDensity(table)
        withExtendedLifetime(density) {
            precondition(!table.usesAutomaticRowHeights && table.rowHeight == 36 && table.intercellSpacing.height == 0)
            for _ in 0..<30 {
                table.usesAutomaticRowHeights = true
                table.rowHeight = 54
                table.intercellSpacing = NSSize(width: 4, height: 12)
                // Do not repeatedly write back against SwiftUI's own updates.
                precondition(table.usesAutomaticRowHeights)
                precondition(table.rowHeight == 54)
                precondition(table.intercellSpacing.height == 12)
            }
        }
        for size in [CGSize(width: 800, height: 560), CGSize(width: 1240, height: 780), CGSize(width: 1800, height: 1100)] {
            for image in [CGSize(width: 1024, height: 1024), CGSize(width: 1600, height: 900), CGSize(width: 600, height: 1200)] {
                let result = CoverCardLayout.placement(in: size, image: image, top: 84, bottom: 150)
                precondition(result.frame.minX >= 40 - 0.001 && result.frame.maxX <= size.width - 40 + 0.001)
                precondition(result.frame.minY >= 84 - 0.001 && result.frame.maxY <= size.height - 150 + 0.001)
                let inner = result.frame.insetBy(dx: result.border, dy: result.border)
                precondition(abs(inner.width / inner.height - image.width / image.height) < 0.0001)
            }
        }
        let empty = CoverCardLayout.placement(in: .zero, image: .zero, top: 84, bottom: 150)
        precondition(empty.frame == .zero)
        print("PASS: initial compact density without KVO write-back; square/portrait/landscape cover fitting preserves toolbar and playback clearance")
    }
}
