import AppKit

enum ResizeBoundary {
    static func contains(_ point: CGPoint, in bounds: CGRect, inset: CGFloat = 10) -> Bool {
        !bounds.insetBy(dx: inset, dy: inset).contains(point)
    }
}
