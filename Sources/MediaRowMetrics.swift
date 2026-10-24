import SwiftUI
import AppKit

enum MediaRowMetrics {
    static let contentHeight: CGFloat = 40
    static let insets = EdgeInsets(top: 3, leading: 10, bottom: 3, trailing: 10)
    static func numberWidth(count: Int) -> CGFloat {
        let digits = String(max(1, count)).count
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let measured = (String(repeating: "9", count: digits) as NSString).size(withAttributes: [.font: font]).width
        return max(30, ceil(measured) + 10)
    }
}
