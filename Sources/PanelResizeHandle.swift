import SwiftUI
import AppKit

struct PanelResizeHandle: View {
    @Binding var width: CGFloat
    let limits: ClosedRange<CGFloat>
    let onEnd: () -> Void
    var growsRight = false
    @State private var hovered = false
    @State private var initialWidth: CGFloat?
    var body: some View {
        Rectangle().fill(.clear)
            .frame(width: 12)
            .contentShape(Rectangle())
            .background(CanvasClickPassthrough(enabled: true))
            .onHover { inside in
                guard inside != hovered else { return }
                hovered = inside
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    if initialWidth == nil { initialWidth = width }
                    var transaction = Transaction(); transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        width = min(limits.upperBound, max(limits.lowerBound, (initialWidth ?? width) + (growsRight ? value.translation.width : -value.translation.width)))
                    }
                }
                .onEnded { _ in initialWidth = nil; onEnd() })
            .onDisappear { if hovered { NSCursor.pop(); hovered = false } }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("调整侧栏宽度")
            .accessibilityValue("\(Int(width))")
            .accessibilityAdjustableAction { direction in
                width = min(limits.upperBound, max(limits.lowerBound, width + (direction == .increment ? 20 : -20)))
                onEnd()
            }
    }
}
